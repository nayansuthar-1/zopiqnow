import { useCallback, useEffect, useState } from 'react'
import { api } from '../lib/api'
import type {
  RestaurantRow,
  RiderEngagement,
  RiderKyc,
  RiderRow,
  Vehicle,
} from '../lib/api'
import { todayLocal } from '../lib/dates'
import {
  signedRiderDocumentUrl,
  uploadRiderDocument,
  UploadFailure,
} from '../lib/uploads'
import type { RiderDocKind } from '../lib/uploads'
import { PageHeader } from '../ui/AppShell'
import {
  Banner,
  Button,
  ConfirmDialog,
  Field,
  Modal,
  Pill,
  Skeleton,
} from '../ui/primitives'

/// The delivery fleet.
///
/// A rider carries orders from any kitchen, which is why this page sits beside
/// Restaurants rather than inside one.
///
/// That used to be the whole truth, and migration 0122 made it three-quarters
/// of it: a `restaurant_owned` rider *is* employed by one kitchen, and the
/// engagement dialog names it. The picker is deliberately confined to that
/// dialog — naming an employer says who pays the rider's wages, not which
/// kitchen may dispatch them, and dispatch is still fleet-wide for everyone.
///
/// Until now the only way onto the fleet was a seed file. That was honest for the
/// first rider and untenable by the tenth.

const vehicles: Vehicle[] = ['bike', 'scooter', 'bicycle']

/// The three engagements, with the sentence each one means for money. Kept
/// beside the list rather than inside the dialog because the row renders the
/// label too, and two spellings of "restaurant's own" would be one edit apart
/// from disagreeing.
const engagements: {
  value: RiderEngagement
  label: string
  blurb: string
}[] = [
  {
    value: 'freelance',
    label: 'Freelance',
    blurb:
      'Works like a Zomato or Swiggy partner. Zopiq pays them per delivery, and they are the only kind that appears in the weekly payout queue.',
  },
  {
    value: 'salaried',
    label: 'Salaried',
    blurb:
      'Paid a wage off the platform. Deliveries still record what the route was worth, so you can see what it cost, but Zopiq never transfers them anything.',
  },
  {
    value: 'restaurant_owned',
    label: "Restaurant's own",
    blurb:
      'The kitchen employs and pays them. Zopiq owes them nothing, and the delivery fee the customer paid stays with Zopiq.',
  },
]

/// Adding and editing are the same four fields, so they are the same form. The
/// only difference is that an existing rider's email is fixed: it is the primary
/// key and the address they sign in with.
function RiderForm({
  editing,
  busy,
  onSubmit,
  onCancel,
}: {
  editing: RiderRow | null
  busy: boolean
  onSubmit: (r: {
    email: string
    name: string
    phone: string
    vehicle: Vehicle
  }) => void
  onCancel: () => void
}) {
  const [email, setEmail] = useState(editing?.email ?? '')
  const [name, setName] = useState(editing?.name ?? '')
  const [phone, setPhone] = useState(editing?.phone ?? '')
  const [vehicle, setVehicle] = useState<Vehicle>(editing?.vehicle ?? 'bike')

  return (
    <form
      className="mt-5 rounded-[8px] border border-line p-4"
      onSubmit={(e) => {
        e.preventDefault()
        onSubmit({ email, name, phone, vehicle })
      }}
    >
      <div className="grid gap-3 sm:grid-cols-2">
        <Field
          label="Name"
          value={name}
          onChange={(e) => setName(e.target.value)}
          placeholder="Ravi Kumar"
        />
        <Field
          label="Phone"
          value={phone}
          onChange={(e) => setPhone(e.target.value)}
          placeholder="9876500011"
          hint="The number a customer rings when their food is late."
        />
        {editing ? (
          <div>
            <span className="mb-1.5 block text-sm font-medium text-ink">Email</span>
            <p className="flex h-11 items-center rounded-[8px] border border-line bg-canvas px-3 text-sm text-ink-muted">
              {editing.email}
            </p>
            <span className="mt-1.5 block text-sm text-ink-muted">
              Can't be changed — it is how they sign in, and every delivery they
              have made hangs off it.
            </span>
          </div>
        ) : (
          <Field
            label="Email"
            type="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            placeholder="ravi@example.com"
            hint="They sign in to the rider app with a code sent here."
          />
        )}
        <label className="block">
          <span className="mb-1.5 block text-sm font-medium text-ink">Vehicle</span>
          <select
            className="h-11 w-full rounded-[8px] border border-line bg-white px-3 text-sm text-ink outline-none focus:border-brand"
            value={vehicle}
            onChange={(e) => setVehicle(e.target.value as Vehicle)}
          >
            {vehicles.map((v) => (
              <option key={v} value={v}>
                {v[0].toUpperCase() + v.slice(1)}
              </option>
            ))}
          </select>
        </label>
      </div>

      <div className="mt-4 flex gap-2">
        <Button type="submit" loading={busy}>
          {editing ? 'Save changes' : 'Add rider'}
        </Button>
        <Button type="button" variant="ghost" onClick={onCancel} disabled={busy}>
          Cancel
        </Button>
      </div>
    </form>
  )
}

export function RidersPage() {
  const [riders, setRiders] = useState<RiderRow[] | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [adding, setAdding] = useState(false)
  const [editing, setEditing] = useState<RiderRow | null>(null)
  const [deactivating, setDeactivating] = useState<RiderRow | null>(null)
  const [banking, setBanking] = useState<RiderRow | null>(null)
  const [verifying, setVerifying] = useState<RiderRow | null>(null)
  const [engaging, setEngaging] = useState<RiderRow | null>(null)

  const load = useCallback(async () => {
    try {
      setRiders(await api.listRiders())
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    }
  }, [])

  useEffect(() => {
    void load()
  }, [load])

  async function run(action: () => Promise<unknown>) {
    setBusy(true)
    setError(null)
    try {
      await action()
      await load()
      return true
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
      return false
    } finally {
      setBusy(false)
    }
  }

  const active = riders?.filter((r) => r.is_active) ?? []
  const waiting = riders?.filter((r) => r.kyc_blocked) ?? []
  // Deliberately surfaced as its own count rather than folded into the happy
  // total. A fleet quietly running on overrides is the failure mode this feature
  // has, and the only defence against it is a number somebody sees every day.
  const cleared = riders?.filter((r) => r.kyc_overridden) ?? []

  return (
    <>
      <PageHeader
        title="Riders"
        subtitle="The delivery fleet. A rider carries orders from any kitchen."
        action={
          !adding && !editing ? (
            <Button onClick={() => setAdding(true)}>Add rider</Button>
          ) : undefined
        }
      />

      <div className="max-w-3xl p-6">
        {error && (
          <Banner tone="error" className="mb-4">{error}</Banner>
        )}

        <div className="rounded-[12px] border border-line bg-white p-6">
          <h2 className="text-base font-bold text-ink">Delivery partners</h2>
          <p className="mt-1 text-sm text-ink-muted">
            {riders === null
              ? 'Loading…'
              : `${active.length} active of ${riders.length}. A rider is offered jobs only once they are active and their documents are verified.`}
          </p>

          {waiting.length > 0 && (
            <Banner tone="warn" className="mt-4">
              {waiting.length === 1
                ? '1 rider cannot take deliveries — their documents are unverified or have expired.'
                : `${waiting.length} riders cannot take deliveries — their documents are unverified or have expired.`}{' '}
              Open Documents on each to check them.
            </Banner>
          )}

          {cleared.length > 0 && (
            <Banner tone="warn" className="mt-4">
              {cleared.length === 1
                ? '1 rider is working without verified documents, because an admin cleared them.'
                : `${cleared.length} riders are working without verified documents, because an admin cleared them.`}{' '}
              Open Documents to see who allowed it and why.
            </Banner>
          )}

          {adding && (
            <RiderForm
              editing={null}
              busy={busy}
              onCancel={() => setAdding(false)}
              onSubmit={(r) =>
                void run(() =>
                  api.addRider(r.email, r.name, r.phone, r.vehicle),
                ).then((ok) => ok && setAdding(false))
              }
            />
          )}

          {editing && (
            <RiderForm
              editing={editing}
              busy={busy}
              onCancel={() => setEditing(null)}
              onSubmit={(r) =>
                void run(() =>
                  api.updateRider(editing.email, r.name, r.phone, r.vehicle),
                ).then((ok) => ok && setEditing(null))
              }
            />
          )}

          {riders !== null && riders.length === 0 && !adding && (
            <p className="mt-5 text-sm text-ink-muted">
              Nobody on the fleet yet. Restaurants can still deliver with their
              own staff — the vendor's own "Hand to rider" button is unaffected.
            </p>
          )}

          {riders !== null && riders.length > 0 && (
            <div className="mt-5 divide-y divide-line rounded-[8px] border border-line">
              {riders.map((r) => (
                <div key={r.email} className="flex flex-wrap items-center gap-3 px-4 py-3">
                  <div className="min-w-0 flex-1">
                    <p className="text-sm font-medium text-ink">
                      {r.name}
                      {!r.is_active && (
                        <span className="ml-2 rounded-full bg-canvas px-2 py-0.5 text-xs font-medium text-ink-muted">
                          inactive
                        </span>
                      )}
                      {r.live_order_id && (
                        <span className="ml-2 rounded-full bg-brand-soft px-2 py-0.5 text-xs font-medium text-brand-deep">
                          carrying {r.live_order_id}
                        </span>
                      )}
                      {/* Three facts, not one. `verified` says an admin read the
                          papers; `blocked` says whether they can work today,
                          and a lapsed insurance separates them; `overridden`
                          says they are working on somebody's say-so and no
                          documents at all. The override is checked first and
                          never renders as "verified" — the whole reason it is
                          stored apart from the status is so this line can tell
                          the truth about why a rider is on the road. */}
                      <span className="ml-2 inline-block align-middle">
                        {r.kyc_overridden ? (
                          <Pill tone="warn">cleared by admin</Pill>
                        ) : r.kyc_status === 'verified' && !r.kyc_blocked ? (
                          <Pill tone="live">verified</Pill>
                        ) : r.kyc_status === 'rejected' ? (
                          <Pill tone="danger">documents rejected</Pill>
                        ) : r.kyc_status === 'verified' ? (
                          <Pill tone="danger">expired</Pill>
                        ) : (
                          <Pill tone="warn">documents pending</Pill>
                        )}
                      </span>
                      {/* Only the exceptions get a pill. Freelance is the
                          default and the overwhelming majority, so badging it
                          would put a label on every row and draw the eye away
                          from the two that actually change what is owed. The
                          engagement is spelled out in the line below either
                          way, so nothing is hidden — this only decides what is
                          worth interrupting for. */}
                      {r.engagement !== 'freelance' && (
                        <span className="ml-2 inline-block align-middle">
                          <Pill tone="neutral">
                            {r.engagement === 'salaried'
                              ? 'salaried · not paid by us'
                              : `${r.employer_name ?? 'restaurant'}'s own · not paid by us`}
                          </Pill>
                        </span>
                      )}
                    </p>
                    <p className="truncate text-sm text-ink-muted">
                      {r.email} · {r.phone} · {r.vehicle} · {r.delivered_count}{' '}
                      delivered
                    </p>
                  </div>

                  <button
                    type="button"
                    disabled={busy}
                    onClick={() => {
                      setAdding(false)
                      setEditing(r)
                    }}
                    className="text-sm font-medium text-ink-muted hover:text-ink disabled:opacity-40"
                  >
                    Edit
                  </button>

                  <button
                    type="button"
                    disabled={busy}
                    onClick={() => setVerifying(r)}
                    className={`text-sm font-medium disabled:opacity-40 ${
                      r.kyc_blocked
                        ? 'text-brand hover:text-brand-deep'
                        : 'text-ink-muted hover:text-ink'
                    }`}
                  >
                    Documents
                  </button>

                  <button
                    type="button"
                    disabled={busy}
                    onClick={() => setBanking(r)}
                    className="text-sm font-medium text-ink-muted hover:text-ink disabled:opacity-40"
                  >
                    Bank
                  </button>

                  <button
                    type="button"
                    disabled={busy}
                    onClick={() => setEngaging(r)}
                    className="text-sm font-medium text-ink-muted hover:text-ink disabled:opacity-40"
                  >
                    Engagement
                  </button>

                  {r.is_active ? (
                    <button
                      type="button"
                      // Greyed out *and* explained. The database refuses this
                      // anyway — the point of doing it here too is that a
                      // disabled button with a reason beats an error after a
                      // click for something ops must never do by accident.
                      disabled={busy || r.live_order_id !== null}
                      onClick={() => setDeactivating(r)}
                      title={
                        r.live_order_id
                          ? `They are carrying ${r.live_order_id}. Release it from Live orders first — that works even if they have stopped answering.`
                          : undefined
                      }
                      className="text-sm font-medium text-ink-muted hover:text-non-veg disabled:opacity-40 disabled:hover:text-ink-muted"
                    >
                      Deactivate
                    </button>
                  ) : (
                    <button
                      type="button"
                      disabled={busy}
                      onClick={() =>
                        void run(() => api.setRiderActive(r.email, true))
                      }
                      className="text-sm font-medium text-brand hover:text-brand-deep disabled:opacity-40"
                    >
                      Reactivate
                    </button>
                  )}
                </div>
              ))}
            </div>
          )}
        </div>
      </div>

      {banking && (
        <BankDialog rider={banking} onClose={() => setBanking(null)} />
      )}

      {engaging && (
        <EngagementDialog
          rider={engaging}
          onClose={(changed) => {
            setEngaging(null)
            if (changed) void load()
          }}
        />
      )}

      {verifying && (
        <KycDialog
          rider={verifying}
          onClose={(changed) => {
            setVerifying(null)
            if (changed) void load()
          }}
        />
      )}

      {deactivating && (
        <ConfirmDialog
          title={`Deactivate ${deactivating.name}?`}
          body="They stop being offered new jobs immediately and cannot use the rider app. Their delivery history is kept, and you can switch them back on at any time."
          confirmLabel="Deactivate"
          busy={busy}
          onCancel={() => setDeactivating(null)}
          onConfirm={() =>
            void run(() => api.setRiderActive(deactivating.email, false)).then(
              (ok) => ok && setDeactivating(null),
            )
          }
        />
      )}
    </>
  )
}

/// One document: upload it, open it for five minutes, or take it off the file.
///
/// Lifted from the restaurant onboarding wizard's `DocumentField` rather than
/// shared with it, because the two differ in the only thing that matters — the
/// bucket — and a single component parameterised by bucket would be one edit
/// away from writing a rider's Aadhaar into the restaurant bucket's blast
/// radius.
function RiderDocField({
  label,
  hint,
  email,
  kind,
  path,
  onChange,
}: {
  label: string
  hint: string
  email: string
  kind: RiderDocKind
  path: string | null
  onChange: (next: string | null) => void
}) {
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function upload(file: File) {
    setBusy(true)
    setError(null)
    try {
      onChange(await uploadRiderDocument(email, kind, file))
    } catch (e) {
      setError(
        e instanceof UploadFailure ? e.message : 'That file could not be uploaded.',
      )
    } finally {
      setBusy(false)
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
              onClick={() => {
                void signedRiderDocumentUrl(path)
                  .then((url) => window.open(url, '_blank', 'noopener'))
                  .catch(() => setError('That document could not be opened.'))
              }}
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

/// A rider's papers, and the decision about them (0080, audit RID-002).
///
/// Everything here is entered by an admin holding the document, never by the
/// rider — the same rule as the bank dialog below and for a stronger reason: a
/// fleet that files its own identity documents is a fleet that files whatever it
/// likes. The rider's app shows them their status and never these fields.
///
/// **A bicycle rider is asked for ID and nothing else.** They have no licence to
/// hold, no insurance to lapse and nothing to register, and the database applies
/// the same rule — so the three sections simply are not drawn.
function KycDialog({
  rider,
  onClose,
}: {
  rider: RiderRow
  onClose: (changed: boolean) => void
}) {
  const [kyc, setKyc] = useState<RiderKyc | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [changed, setChanged] = useState(false)
  const [rejecting, setRejecting] = useState(false)
  const [reason, setReason] = useState('')
  const [clearing, setClearing] = useState(false)
  const [clearReason, setClearReason] = useState('')
  const [clearUntil, setClearUntil] = useState('')

  const motorised = rider.vehicle !== 'bicycle'

  const [licence, setLicence] = useState('')
  const [licenceExpiry, setLicenceExpiry] = useState('')
  const [licenceDoc, setLicenceDoc] = useState<string | null>(null)
  const [policy, setPolicy] = useState('')
  const [policyExpiry, setPolicyExpiry] = useState('')
  const [policyDoc, setPolicyDoc] = useState<string | null>(null)
  const [idKind, setIdKind] = useState<'aadhaar' | 'pan'>('aadhaar')
  const [idNumber, setIdNumber] = useState('')
  const [idDoc, setIdDoc] = useState<string | null>(null)
  const [plate, setPlate] = useState('')
  const [rcDoc, setRcDoc] = useState<string | null>(null)

  useEffect(() => {
    let alive = true
    void api
      .getRiderKyc(rider.email)
      .then((rows) => {
        if (!alive) return
        const k = rows[0] ?? null
        if (k) {
          setLicence(k.licence_number ?? '')
          setLicenceExpiry(k.licence_expiry ?? '')
          setLicenceDoc(k.licence_doc_path)
          setPolicy(k.insurance_policy ?? '')
          setPolicyExpiry(k.insurance_expiry ?? '')
          setPolicyDoc(k.insurance_doc_path)
          setIdKind(k.id_proof_kind ?? 'aadhaar')
          setIdNumber(k.id_proof_number ?? '')
          setIdDoc(k.id_proof_doc_path)
          setPlate(k.vehicle_number ?? '')
          setRcDoc(k.rc_doc_path)
        }
        setKyc(k)
      })
      .catch((e: unknown) => {
        if (alive) setError(e instanceof Error ? e.message : String(e))
      })
    return () => {
      alive = false
    }
  }, [rider.email])

  const today = todayLocal()

  async function run(action: () => Promise<unknown>) {
    setBusy(true)
    setError(null)
    try {
      await action()
      setChanged(true)
      // Re-read rather than guess: `status` moves on save as well as on review,
      // and the blocked sentence is computed in the database.
      const rows = await api.getRiderKyc(rider.email)
      setKyc(rows[0] ?? null)
      return true
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
      return false
    } finally {
      setBusy(false)
    }
  }

  const save = () =>
    run(() =>
      api.setRiderKyc(rider.email, {
        licence_number: licence,
        // An empty date string is no date, not the epoch.
        licence_expiry: licenceExpiry === '' ? null : licenceExpiry,
        licence_doc_path: licenceDoc,
        insurance_policy: policy,
        insurance_expiry: policyExpiry === '' ? null : policyExpiry,
        insurance_doc_path: policyDoc,
        id_proof_kind: idNumber === '' ? null : idKind,
        id_proof_number: idNumber,
        id_proof_doc_path: idDoc,
        vehicle_number: plate,
        rc_doc_path: rcDoc,
      }),
    )

  return (
    <Modal busy={busy} onClose={() => onClose(changed)} title={`Documents · ${rider.name}`}>
      <p className="text-sm text-ink-muted">
        Entered by Zopiqnow from the originals, never by the rider. Until these
        are verified they cannot go online, see the board, or be offered a job.
      </p>

      {error && (
        <Banner tone="error" className="mt-4" onDismiss={() => setError(null)}>
          {error}
        </Banner>
      )}

      {kyc === null && !error ? (
        <div className="mt-5 space-y-3">
          <Skeleton className="h-11 w-full" />
          <Skeleton className="h-11 w-full" />
          <Skeleton className="h-11 w-full" />
        </div>
      ) : (
        <>
          {/* The override is stated first and in its own words. Falling through
              to "Verified" here would be the console telling an admin that
              somebody read the documents when nobody did. */}
          {kyc?.override_active ? (
            <Banner tone="warn" className="mt-4">
              Working without verified documents.
              {kyc.override_by ? ` Cleared by ${kyc.override_by}` : ' Cleared'}
              {kyc.override_at
                ? ` on ${new Date(kyc.override_at).toLocaleDateString()}`
                : ''}
              {kyc.override_until
                ? `, until ${new Date(kyc.override_until).toLocaleDateString()}`
                : ', with no end date'}
              . “{kyc.override_reason}”
            </Banner>
          ) : kyc?.blocked_reason ? (
            <Banner tone="warn" className="mt-4">
              {kyc.blocked_reason}
            </Banner>
          ) : (
            <Banner tone="success" className="mt-4">
              Verified
              {kyc?.reviewed_by ? ` by ${kyc.reviewed_by}` : ''}
              {kyc?.reviewed_at
                ? ` on ${new Date(kyc.reviewed_at).toLocaleDateString()}`
                : ''}
              . They can take deliveries.
            </Banner>
          )}

          <form
            className="mt-5 grid gap-5"
            onSubmit={(e) => {
              e.preventDefault()
              void save()
            }}
          >
            {motorised && (
              <>
                <div className="grid gap-4 sm:grid-cols-2">
                  <Field
                    label="Driving licence number"
                    value={licence}
                    onChange={(e) => setLicence(e.target.value.toUpperCase())}
                    placeholder="MH0220110149646"
                    hint="Formats differ by state — copy it exactly as printed."
                  />
                  <Field
                    label="Licence expiry"
                    type="date"
                    value={licenceExpiry}
                    onChange={(e) => setLicenceExpiry(e.target.value)}
                    error={
                      licenceExpiry !== '' && licenceExpiry < today
                        ? 'This licence has already expired.'
                        : undefined
                    }
                    hint="They stop being offered jobs the day this passes."
                  />
                </div>
                <RiderDocField
                  label="Licence scan"
                  hint="PDF or photo, up to 10 MB. Stored privately — links expire after five minutes."
                  email={rider.email}
                  kind="licence"
                  path={licenceDoc}
                  onChange={setLicenceDoc}
                />

                <div className="grid gap-4 sm:grid-cols-2">
                  <Field
                    label="Insurance policy number"
                    value={policy}
                    onChange={(e) => setPolicy(e.target.value.toUpperCase())}
                    placeholder="POL123456789"
                    hint="Third-party cover is compulsory for a motorised vehicle."
                  />
                  <Field
                    label="Insurance expiry"
                    type="date"
                    value={policyExpiry}
                    onChange={(e) => setPolicyExpiry(e.target.value)}
                    error={
                      policyExpiry !== '' && policyExpiry < today
                        ? 'This policy has already expired.'
                        : undefined
                    }
                  />
                </div>
                <RiderDocField
                  label="Insurance certificate"
                  hint="PDF or photo, up to 10 MB."
                  email={rider.email}
                  kind="insurance"
                  path={policyDoc}
                  onChange={setPolicyDoc}
                />
              </>
            )}

            <div className="grid gap-4 sm:grid-cols-2">
              <label className="block">
                <span className="mb-1.5 block text-sm font-medium text-ink">
                  ID proof
                </span>
                <select
                  className="h-11 w-full rounded-[8px] border border-line bg-white px-3 text-sm text-ink outline-none focus:border-brand"
                  value={idKind}
                  onChange={(e) => setIdKind(e.target.value as 'aadhaar' | 'pan')}
                >
                  <option value="aadhaar">Aadhaar</option>
                  <option value="pan">PAN</option>
                </select>
              </label>
              <Field
                label={idKind === 'aadhaar' ? 'Aadhaar number' : 'PAN'}
                value={idNumber}
                maxLength={idKind === 'aadhaar' ? 12 : 10}
                onChange={(e) =>
                  setIdNumber(
                    idKind === 'aadhaar'
                      ? e.target.value.replace(/\D/g, '')
                      : e.target.value.toUpperCase(),
                  )
                }
                placeholder={idKind === 'aadhaar' ? '123456789012' : 'ABCDE1234F'}
                hint={idKind === 'aadhaar' ? '12 digits.' : 'Ten characters.'}
              />
            </div>
            <RiderDocField
              label={idKind === 'aadhaar' ? 'Aadhaar card' : 'PAN card'}
              hint="Asked of every rider, including bicycles."
              email={rider.email}
              kind="id"
              path={idDoc}
              onChange={setIdDoc}
            />

            {motorised && (
              <>
                <Field
                  label="Vehicle registration number"
                  value={plate}
                  onChange={(e) => setPlate(e.target.value.toUpperCase())}
                  placeholder="MH12AB1234"
                  hint="Spaces and hyphens are stripped on save."
                />
                <RiderDocField
                  label="RC book"
                  hint="So an incident can be traced to a vehicle and not only to a person."
                  email={rider.email}
                  kind="rc"
                  path={rcDoc}
                  onChange={setRcDoc}
                />
              </>
            )}

            <p className="text-sm text-ink-muted">
              Saving sends this rider back to <strong>pending</strong>, including
              a typo fix — "verified" has to mean somebody read what is on file
              now.
            </p>

            <div className="flex flex-wrap justify-end gap-2">
              <Button
                type="button"
                variant="ghost"
                onClick={() => onClose(changed)}
                disabled={busy}
              >
                Close
              </Button>
              <Button type="submit" variant="secondary" loading={busy}>
                Save
              </Button>
              {kyc?.override_active ? (
                <Button
                  type="button"
                  variant="secondary"
                  loading={busy}
                  onClick={() =>
                    void run(() => api.overrideRiderKyc(rider.email, false))
                  }
                >
                  End clearance
                </Button>
              ) : (
                <Button
                  type="button"
                  variant="ghost"
                  disabled={busy}
                  onClick={() => setClearing(true)}
                >
                  Let them work anyway…
                </Button>
              )}
              <Button
                type="button"
                variant="secondary"
                disabled={busy}
                onClick={() => setRejecting(true)}
              >
                Reject…
              </Button>
              <Button
                type="button"
                loading={busy}
                onClick={() => void run(() => api.reviewRiderKyc(rider.email, true))}
              >
                Verify
              </Button>
            </div>
          </form>
        </>
      )}

      {clearing && (
        <Modal
          busy={busy}
          onClose={() => setClearing(false)}
          title="Let them work without documents"
        >
          <p className="text-sm text-ink-muted">
            This puts the rider on the road now, carrying orders to customers'
            homes, without anybody having checked their licence, insurance or
            ID. It does not mark their documents as seen — it records that{' '}
            <strong>you</strong> decided to do without them.
          </p>
          <Field
            className="mt-4"
            label="Why"
            value={clearReason}
            onChange={(e) => setClearReason(e.target.value)}
            placeholder="Known to the owner. Bringing the licence on Monday."
          />
          <Field
            className="mt-4"
            type="date"
            label="Until (optional)"
            value={clearUntil}
            onChange={(e) => setClearUntil(e.target.value)}
            hint={
              'Leave it empty and this never ends on its own. Setting a date is ' +
              'how "bringing it on Monday" actually means Monday.'
            }
          />
          <div className="mt-4 flex justify-end gap-2">
            <Button
              type="button"
              variant="secondary"
              onClick={() => setClearing(false)}
              disabled={busy}
            >
              Cancel
            </Button>
            <Button
              type="button"
              loading={busy}
              onClick={() =>
                void run(() =>
                  api.overrideRiderKyc(
                    rider.email,
                    true,
                    clearReason,
                    clearUntil || null,
                  ),
                ).then((ok) => {
                  if (ok) {
                    setClearing(false)
                    setClearReason('')
                    setClearUntil('')
                  }
                })
              }
            >
              Let them work
            </Button>
          </div>
        </Modal>
      )}

      {rejecting && (
        <Modal busy={busy} onClose={() => setRejecting(false)} title="Reject documents">

          <p className="text-sm text-ink-muted">
            The rider is sent this word for word, in the app and as a
            notification. Say what they need to do.
          </p>
          <Field
            className="mt-4"
            label="Reason"
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            placeholder="The licence scan is too blurry to read."
          />
          <div className="mt-4 flex justify-end gap-2">
            <Button
              type="button"
              variant="secondary"
              onClick={() => setRejecting(false)}
              disabled={busy}
            >
              Cancel
            </Button>
            <Button
              type="button"
              loading={busy}
              onClick={() =>
                void run(() =>
                  api.reviewRiderKyc(rider.email, false, reason),
                ).then((ok) => {
                  if (ok) {
                    setRejecting(false)
                    setReason('')
                  }
                })
              }
            >
              Reject
            </Button>
          </div>
        </Modal>
      )}
    </Modal>
  )
}

/// Where a rider's pay is sent.
///
/// Entered here and never by the rider, which is the whole reason this dialog
/// exists rather than a screen in the rider app: a rider who can write their own
/// payout destination is the entire fraud surface of a payout system in one form
/// field. Same rule 0009 set for restaurant onboarding and 0040 reaffirmed for
/// this roster.
///
/// Saving a different account clears `verified` in the database — whoever checked
/// the old one against a document did not check this one.
function BankDialog({ rider, onClose }: { rider: RiderRow; onClose: () => void }) {
  const [holder, setHolder] = useState('')
  const [account, setAccount] = useState('')
  const [ifsc, setIfsc] = useState('')
  const [bank, setBank] = useState('')
  const [loaded, setLoaded] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    let alive = true
    void api
      .getRiderBank(rider.email)
      .then((rows) => {
        if (!alive) return
        const b = rows[0]
        if (b) {
          setHolder(b.account_holder ?? '')
          setAccount(b.account_number ?? '')
          setIfsc(b.ifsc ?? '')
          setBank(b.bank_name ?? '')
        }
        setLoaded(true)
      })
      .catch((e: unknown) => {
        if (alive) setError(e instanceof Error ? e.message : String(e))
      })
    return () => {
      alive = false
    }
  }, [rider.email])

  return (
    <Modal
      busy={busy}
      onClose={onClose}
      title={`Bank details · ${rider.name}`}
    >
      <p className="text-sm text-ink-muted">
        Where their weekly payout is sent. The rider never sees or edits this.
      </p>

      {error && (
        <Banner tone="error" className="mt-4" onDismiss={() => setError(null)}>
          {error}
        </Banner>
      )}

      {!loaded ? (
        <div className="mt-5 space-y-3">
          <Skeleton className="h-11 w-full" />
          <Skeleton className="h-11 w-full" />
          <Skeleton className="h-11 w-full" />
        </div>
      ) : (
        <form
          className="mt-5 grid gap-4"
          onSubmit={(e) => {
              e.preventDefault()
              setBusy(true)
              setError(null)
              void api
                .setRiderBank(rider.email, {
                  account_holder: holder,
                  account_number: account,
                  ifsc,
                  bank_name: bank,
                })
                .then(onClose)
                .catch((err: unknown) =>
                  setError(err instanceof Error ? err.message : String(err)),
                )
                .finally(() => setBusy(false))
            }}
          >
            <Field
              label="Account holder"
              value={holder}
              onChange={(e) => setHolder(e.target.value)}
              placeholder="As printed on the passbook"
            />
            <Field
              label="Account number"
              value={account}
              onChange={(e) => setAccount(e.target.value)}
              placeholder="123456789012"
              hint="9 to 18 digits."
            />
            <Field
              label="IFSC"
              value={ifsc}
              onChange={(e) => setIfsc(e.target.value)}
              placeholder="SBIN0001234"
              // Upper-cased server-side, so a rider's handwriting copied in
              // lower case is not an error worth showing anybody.
              hint="Eleven characters. Case does not matter."
            />
            <Field
              label="Bank name"
              value={bank}
              onChange={(e) => setBank(e.target.value)}
              placeholder="State Bank of India"
            />
          <div className="flex justify-end gap-2">
            <Button
              type="button"
              variant="secondary"
              onClick={onClose}
              disabled={busy}
            >
              Cancel
            </Button>
            <Button type="submit" loading={busy}>
              Save
            </Button>
          </div>
        </form>
      )}
    </Modal>
  )
}

/// On what terms a rider is engaged — which is the only thing deciding whether
/// the weekly batch ever creates a payout for them (migration 0122).
///
/// The consequence is spelled out under every option rather than in a help link,
/// because this is the one screen on the fleet page that decides whether somebody
/// gets paid, and "salaried" does not tell you on its own that Zopiq will now
/// transfer them nothing.
///
/// The restaurant list is fetched only when it is needed — a picker that is
/// hidden for two of the three options should not cost a round trip for them.
function EngagementDialog({
  rider,
  onClose,
}: {
  rider: RiderRow
  onClose: (changed: boolean) => void
}) {
  const [engagement, setEngagement] = useState<RiderEngagement>(rider.engagement)
  const [employer, setEmployer] = useState<string>(
    rider.employer_restaurant_id ?? '',
  )
  const [restaurants, setRestaurants] = useState<RestaurantRow[] | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const needsEmployer = engagement === 'restaurant_owned'

  useEffect(() => {
    if (!needsEmployer || restaurants !== null) return
    let alive = true
    void api
      .listRestaurants()
      .then((rows) => {
        if (alive) setRestaurants(rows)
      })
      .catch((e: unknown) => {
        if (alive) setError(e instanceof Error ? e.message : String(e))
      })
    return () => {
      alive = false
    }
  }, [needsEmployer, restaurants])

  return (
    <Modal
      busy={busy}
      onClose={() => onClose(false)}
      title={`Engagement · ${rider.name}`}
    >
      <p className="text-sm text-ink-muted">
        How this rider is engaged, and therefore whether Zopiq owes them money at
        all. Deliveries always record what the route was worth — this decides
        whether that amount is ever transferred.
      </p>

      {error && (
        <Banner tone="error" className="mt-4" onDismiss={() => setError(null)}>
          {error}
        </Banner>
      )}

      <form
        className="mt-5 grid gap-4"
        onSubmit={(e) => {
          e.preventDefault()
          setBusy(true)
          setError(null)
          void api
            .setRiderEngagement(
              rider.email,
              engagement,
              // The database constrains the pair together, so an employer left
              // over from a previous choice must not be sent with an engagement
              // that forbids one.
              needsEmployer ? employer : null,
            )
            .then(() => onClose(true))
            .catch((err: unknown) =>
              setError(err instanceof Error ? err.message : String(err)),
            )
            .finally(() => setBusy(false))
        }}
      >
        <fieldset className="grid gap-2">
          <legend className="sr-only">Engagement</legend>
          {engagements.map((o) => (
            <label
              key={o.value}
              className={`flex cursor-pointer gap-3 rounded-[8px] border p-3 ${
                engagement === o.value
                  ? 'border-brand bg-brand-soft/40'
                  : 'border-line hover:bg-canvas'
              }`}
            >
              <input
                type="radio"
                name="engagement"
                className="mt-1"
                value={o.value}
                checked={engagement === o.value}
                onChange={() => setEngagement(o.value)}
              />
              <span>
                <span className="block text-sm font-semibold text-ink">
                  {o.label}
                </span>
                <span className="mt-0.5 block text-sm text-ink-muted">
                  {o.blurb}
                </span>
              </span>
            </label>
          ))}
        </fieldset>

        {needsEmployer &&
          (restaurants === null ? (
            <Skeleton className="h-11 w-full" />
          ) : (
            <label className="grid gap-1.5">
              <span className="text-sm font-medium text-ink">
                Which restaurant employs them?
              </span>
              <select
                value={employer}
                onChange={(e) => setEmployer(e.target.value)}
                required
                className="h-11 rounded-[8px] border border-line bg-white px-3 text-sm text-ink"
              >
                <option value="">Choose a restaurant…</option>
                {restaurants.map((r) => (
                  <option key={r.id} value={r.id}>
                    {r.name}
                  </option>
                ))}
              </select>
            </label>
          ))}

        <div className="flex justify-end gap-2">
          <Button
            type="button"
            variant="secondary"
            onClick={() => onClose(false)}
            disabled={busy}
          >
            Cancel
          </Button>
          <Button type="submit" loading={busy} disabled={needsEmployer && !employer}>
            Save
          </Button>
        </div>
      </form>
    </Modal>
  )
}
