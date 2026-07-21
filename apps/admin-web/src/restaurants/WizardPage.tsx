import { useCallback, useEffect, useState } from 'react'
import { useLocation, useNavigate, useParams } from 'react-router-dom'
import { api } from '../lib/api'
import type { RestaurantDetail } from '../lib/api'
import { PageHeader } from '../ui/AppShell'
import { StorefrontStep } from './steps/StorefrontStep'
import { AddressStep } from './steps/AddressStep'
import { LegalStep } from './steps/LegalStep'
import { BankStep } from './steps/BankStep'
import { HoursStep } from './steps/HoursStep'
import { TeamStep } from './steps/TeamStep'
import { MenuStep } from '../menu/MenuStep'
import { ReviewStep } from './steps/ReviewStep'

/// The onboarding wizard, and the reason it is a wizard rather than one long form:
/// a restaurant is six unrelated conversations (what it sells, where it is, what it
/// is licensed to do, who to pay, when it opens, who runs it) and nobody has all six
/// answers to hand at once.
///
/// **The draft is the persistence.** Step 1 creates a real row — inactive, invisible
/// to customers — and every later step saves against its id. There is no
/// half-filled state living in the browser to lose. Closing the tab three steps in
/// costs nothing, and the restaurant shows up in the list as a Draft with the work
/// that is left visible on it.

const steps = [
  { key: 'storefront', label: 'Storefront' },
  { key: 'address', label: 'Address' },
  { key: 'legal', label: 'Legal' },
  { key: 'bank', label: 'Bank' },
  { key: 'hours', label: 'Hours' },
  { key: 'team', label: 'Team' },
  { key: 'menu', label: 'Menu' },
  { key: 'review', label: 'Review' },
] as const

export function WizardPage() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const location = useLocation()

  const [detail, setDetail] = useState<RestaurantDetail | null>(null)
  // Creating the draft changes the URL from /new to /:id, which is a different
  // route and therefore a fresh mount — the step counter in the old one dies with
  // it. Carried across in navigation state so "Create draft" lands on step 2
  // rather than silently back on step 1.
  const [step, setStep] = useState(
    (location.state as { step?: number } | null)?.step ?? 0,
  )
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(Boolean(id))

  const reload = useCallback(async () => {
    if (!id) return
    try {
      setDetail(await api.getRestaurant(id))
      setError(null)
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setLoading(false)
    }
  }, [id])

  useEffect(() => {
    void reload()
  }, [reload])

  /// Step 1 on a new restaurant: the row does not exist until this returns, so the
  /// URL changes with it. `replace` rather than push — the /new page is not
  /// somewhere Back should ever return to, because going there again would create
  /// a second restaurant.
  function onCreated(newId: string) {
    navigate(`/restaurants/${newId}`, { replace: true, state: { step: 1 } })
  }

  if (loading) {
    return (
      <>
        <PageHeader title="Restaurant" />
        <p className="p-6 text-sm text-ink-muted">Loading…</p>
      </>
    )
  }

  const r = detail?.restaurant

  return (
    <>
      <PageHeader
        title={r ? r.name : 'Add restaurant'}
        subtitle={
          r
            ? r.is_active
              ? 'Live — changes take effect immediately'
              : 'Draft — not visible to customers yet'
            : 'Step 1 creates the draft. Nothing is public until you publish.'
        }
      />

      <div className="border-b border-line bg-white px-6">
        <div className="flex gap-1 overflow-x-auto">
          {steps.map((s, i) => {
            const reachable = Boolean(id) || i === 0
            return (
              <button
                key={s.key}
                disabled={!reachable}
                onClick={() => setStep(i)}
                className={`shrink-0 border-b-2 px-3 py-3 text-sm font-medium transition-colors ${
                  step === i
                    ? 'border-brand text-brand-deep'
                    : reachable
                      ? 'border-transparent text-ink-muted hover:text-ink'
                      : 'border-transparent text-ink-muted/40'
                }`}
              >
                <span className="mr-1.5 text-xs tabular-nums">{i + 1}</span>
                {s.label}
              </button>
            )
          })}
        </div>
      </div>

      <div className="p-6">
        {error && (
          <p className="mb-4 max-w-2xl rounded-[8px] bg-non-veg-soft px-4 py-3 text-sm text-non-veg">
            {error}
          </p>
        )}

        {/* The menu is a list of lists and needs the width; the forms read better
            narrow. */}
        <div className={step === 6 ? 'max-w-4xl' : 'max-w-2xl'}>
          {step === 0 && (
            <StorefrontStep
              detail={detail}
              onCreated={onCreated}
              onSaved={reload}
              onNext={() => setStep(1)}
            />
          )}
          {step === 1 && id && (
            <AddressStep id={id} detail={detail} onSaved={reload} onNext={() => setStep(2)} />
          )}
          {step === 2 && id && (
            <LegalStep id={id} detail={detail} onSaved={reload} onNext={() => setStep(3)} />
          )}
          {step === 3 && id && (
            <BankStep id={id} detail={detail} onSaved={reload} onNext={() => setStep(4)} />
          )}
          {step === 4 && id && (
            <HoursStep id={id} detail={detail} onSaved={reload} onNext={() => setStep(5)} />
          )}
          {step === 5 && id && (
            <TeamStep id={id} detail={detail} onSaved={reload} onNext={() => setStep(6)} />
          )}
          {step === 6 && id && <MenuStep id={id} onNext={() => setStep(7)} />}
          {step === 7 && id && (
            <ReviewStep
              id={id}
              detail={detail}
              onSaved={reload}
              onGoToStep={setStep}
            />
          )}
        </div>
      </div>
    </>
  )
}
