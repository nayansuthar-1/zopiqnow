import { useCallback, useEffect, useState } from 'react'
import { useLocation, useNavigate, useParams } from 'react-router-dom'
import { api } from '../lib/api'
import type { MenuItemRow, RestaurantDetail } from '../lib/api'
import { PageHeader } from '../ui/AppShell'
import {
  Banner,
  CardSkeleton,
  Icon,
  PageBody,
} from '../ui/primitives'
import { checksFor } from './checklist'
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
  /// The menu, only so the step bar can say whether the Menu step is done.
  /// `MenuStep` owns the real copy and pushes every load here; this fetch is the
  /// first one, for the case where somebody opens the wizard on step 1 and never
  /// goes near the Menu tab. `null` is "not asked yet", which reads as no tick
  /// rather than as a failure.
  const [menu, setMenu] = useState<MenuItemRow[] | null>(null)
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

  useEffect(() => {
    if (!id) return
    // Quietly: a step bar that cannot be ticked is not worth an error banner
    // over, and every screen that acts on the menu reports its own failures.
    api.listMenu(id).then(setMenu, () => {})
  }, [id])

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
        <PageBody width="form">
          <CardSkeleton rows={2} />
        </PageBody>
      </>
    )
  }

  const r = detail?.restaurant

  /// Which steps are finished, from the same `checksFor` the Review step reads.
  ///
  /// **A tick means "nothing left here", not "you have been here".** Whether a
  /// step was visited is not a thing the wizard knows or a thing anybody needs;
  /// what an admin on step 7 wants to know is which of the first six still owe
  /// something, and that is the question the checklist already answers. So
  /// Storefront stays unticked while the cover photo is missing even though the
  /// row saved — which is the same sentence the Review step will print.
  ///
  /// A step is done when every check filed under it passes. A step with no checks
  /// at all — Review, which is the action rather than a thing to complete — is
  /// never ticked, and before the draft exists there is no `detail` and so no
  /// ticks at all.
  const done = new Set<number>()
  if (detail) {
    const checks = checksFor(detail, menu ?? [])
    for (const i of new Set(checks.map((c) => c.step))) {
      if (checks.every((c) => c.step !== i || c.done)) done.add(i)
    }
    // The menu has not come back yet, so "no sellable dish" is not something we
    // know — only something we have not been told. Better a missing tick than a
    // wrong one.
    if (menu === null) done.delete(6)
  }

  return (
    <>
      {/* The header and the step bar are one thing and stick as one. Left to
          itself the bar scrolled away on the Menu step — the only step long
          enough to scroll — leaving a sticky header above a page whose eight
          steps were no longer on screen. */}
      <div className="sticky top-0 z-20">
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
              const ticked = done.has(i)
              return (
                <button
                  key={s.key}
                  disabled={!reachable}
                  onClick={() => setStep(i)}
                  className={`shrink-0 border-b-2 px-3 py-3 text-sm font-medium transition-colors ${
                    step === i
                      ? 'border-brand-ink text-brand-ink'
                      : reachable
                        ? 'border-transparent text-ink-muted hover:text-ink'
                        : // 3.08:1, up from 1.80. A step you cannot reach yet
                          // still has to be readable — it is how you find out
                          // what the wizard is going to ask for. WCAG exempts
                          // an inactive control from the text minimum, which is
                          // an argument for not colouring it like an error, not
                          // an argument for making it invisible.
                          'cursor-not-allowed border-transparent text-ink-muted/70'
                  }`}
                >
                  {/* The tick takes the number's place rather than sitting
                      beside it: the step bar is already eight items wide on a
                      laptop, and a step you have finished is not one you are
                      counting to any more. It is a shape and not just a colour,
                      and the word behind it is there for a screen reader. */}
                  {ticked ? (
                    <>
                      <Icon
                        name="checkCircle"
                        className="mr-1.5 inline-block size-4 align-[-3px] text-veg"
                      />
                      <span className="sr-only">Done. </span>
                    </>
                  ) : (
                    <span className="mr-1.5 text-xs tabular-nums">{i + 1}</span>
                  )}
                  {s.label}
                </button>
              )
            })}
          </div>
        </div>
      </div>

      <div className="p-6">
        {error && (
          <Banner
            tone="error"
            className="mb-4 max-w-2xl"
            onDismiss={() => setError(null)}
          >
            {error}
          </Banner>
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
          {step === 6 && id && (
            <MenuStep id={id} onNext={() => setStep(7)} onLoaded={setMenu} />
          )}
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
