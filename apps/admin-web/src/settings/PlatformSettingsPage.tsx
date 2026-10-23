import { useCallback, useEffect, useState } from 'react'
import type { ReactNode } from 'react'
import { Link } from 'react-router-dom'
import { api } from '../lib/api'
import type { PlatformSettings } from '../lib/api'
import { PageHeader } from '../ui/AppShell'
import {
  Banner,
  Button,
  Card,
  CardSkeleton,
  ConfirmDialog,
  Field,
  PageBody,
  Pill,
  Select,
  Toggle,
} from '../ui/primitives'
import { useToast } from '../ui/toast'
import { inr } from '../lib/money'

/// The levers that used to need a psql session (migration 0159).
///
/// Four settings tables, each one row, each holding numbers that are a
/// judgement about this town on this evening rather than a fact about the
/// software — and each, until now, costing a migration to change. Two minutes is
/// right for Sadri at eight o'clock and wrong for a wedding weekend when every
/// kitchen is under water.
///
/// Every field here says what it *means* rather than what it is called. A form
/// of eight labelled numbers is a form somebody changes the wrong one on.

/// The four slabs `admin_set_tax_settings` accepts, which are the four
/// `menu_items.gst_rate_bps` is checked against. A free-text basis-point box on
/// a tax rate is a form where 18 means 0.18%, and the mistake shows up on a
/// numbered invoice rather than on the screen.
const SLABS = [0, 500, 1200, 1800] as const

/// Basis points as somebody reads them. All four slabs are whole percents.
function slabLabel(bps: number): string {
  return bps === 0 ? 'Nil (0%)' : `${bps / 100}%`
}

function Section({
  title,
  blurb,
  children,
  footer,
}: {
  title: string
  blurb: ReactNode
  children: ReactNode
  footer?: ReactNode
}) {
  return (
    <Card>
      <h2 className="text-base font-bold text-ink">{title}</h2>
      <p className="mt-1 max-w-2xl text-sm text-ink-muted">{blurb}</p>
      <div className="mt-5">{children}</div>
      {footer && <div className="mt-5 flex items-center gap-3">{footer}</div>}
    </Card>
  )
}

export function PlatformSettingsPage() {
  const toast = useToast()
  const [settings, setSettings] = useState<PlatformSettings | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState<string | null>(null)
  const [gate, setGate] = useState<boolean | null>(null)

  // Edited copies. Held apart from `settings` so a half-typed number is never
  // what the next save sends, and so Cancel has something to go back to.
  const [dispatch, setDispatch] = useState<PlatformSettings['dispatch'] | null>(null)
  const [surcharge, setSurcharge] = useState<PlatformSettings['surcharge'] | null>(null)
  /// One number rather than the row: nothing else on the delivery-fee table is
  /// editable, and `null` is the not-loaded-yet state the guard below reads.
  const [fee, setFee] = useState<number | null>(null)
  /// The two GST rates. `food_slabs_in_use` rides along on the same row and is
  /// read-only, so the edited copy carries the whole row and sends two fields.
  const [tax, setTax] = useState<PlatformSettings['tax'] | null>(null)

  const load = useCallback(async () => {
    try {
      const next = await api.platformSettings()
      setSettings(next)
      setDispatch(next.dispatch)
      setSurcharge(next.surcharge)
      setFee(next.delivery.base_fee)
      setTax(next.tax)
      setError(null)
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    }
  }, [])

  useEffect(() => {
    void load()
  }, [load])

  async function save(what: string, action: () => Promise<string>) {
    setBusy(what)
    setError(null)
    try {
      toast(await action())
      await load()
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(null)
    }
  }

  if (!settings || !dispatch || !surcharge || !tax || fee === null) {
    return (
      <>
        <PageHeader title="Platform settings" />
        <PageBody width="form">
          {error ? (
            <Banner tone="error">{error}</Banner>
          ) : (
            <CardSkeleton rows={5} />
          )}
        </PageBody>
      </>
    )
  }

  const num =
    (set: (v: number) => void) =>
    (e: { target: { value: string } }) =>
      set(Number(e.target.value))

  return (
    <>
      <PageHeader
        title="Platform settings"
        subtitle="How the network dispatches, what it charges after dark, and whether it trusts a payment."
      />

      <PageBody width="form" className="space-y-6">
        {error && (
          <Banner tone="error" onDismiss={() => setError(null)}>
            {error}
          </Banner>
        )}

        {/* ------------------------------------------------------------- */}
        <Section
          title="Payment verification"
          blurb={
            <>
              With this on, an order whose payment Razorpay has not confirmed is
              refused before the kitchen ever sees it. It has been on since
              29 August. Turning it <strong>off</strong> lets orders through
              unproved — which is occasionally the right call at three in the
              morning when verification itself is down, and is never the right
              state to leave it in.
            </>
          }
        >
          <div className="flex flex-wrap items-center gap-4">
            <Pill tone={settings.payments.require_verified_payment ? 'live' : 'danger'}>
              {settings.payments.require_verified_payment ? 'On' : 'OFF'}
            </Pill>
            <Button
              variant={settings.payments.require_verified_payment ? 'danger' : 'primary'}
              loading={busy === 'gate'}
              onClick={() => setGate(!settings.payments.require_verified_payment)}
            >
              {settings.payments.require_verified_payment
                ? 'Turn it off'
                : 'Turn it back on'}
            </Button>
            {/* The number that says what leaving it off has cost, or what
                arming it would refuse. Zero is the answer to hope for. */}
            <span className="text-sm text-ink-muted">
              {settings.payments.unverified_live_orders === 0
                ? 'No live order is missing a verified payment.'
                : `${settings.payments.unverified_live_orders} live order(s) have no verified payment behind them.`}
            </span>
          </div>
        </Section>

        {/* ------------------------------------------------------------- */}
        <Section
          title="Delivery fee"
          blurb={
            <>
              What every order pays for the ride, before the night and rain
              surcharge below is added and before a free-delivery coupon waives
              it. GST is <strong>inside</strong> this number, not added to it —
              type 40 and the customer's bill says ₹40. It applies to orders
              placed after you save; what somebody was already charged is frozen
              on their order. Riders are paid by distance and are not affected.
            </>
          }
          footer={
            <>
              <Button
                loading={busy === 'fee'}
                onClick={() => void save('fee', () => api.setDeliveryFee(fee))}
              >
                Save delivery fee
              </Button>
              <Button
                variant="ghost"
                onClick={() => setFee(settings.delivery.base_fee)}
                disabled={busy !== null}
              >
                Reset
              </Button>
            </>
          }
        >
          <Field
            label="Delivery fee, rupees"
            type="number"
            value={String(fee)}
            onChange={num(setFee)}
            hint={
              fee === 0
                ? 'Zero means delivery is free on every order, for everybody, until this is changed back.'
                : `Every customer sees ${inr(fee)} on the bill.`
            }
          />
        </Section>

        {/* ------------------------------------------------------------- */}
        <Section
          title="GST"
          blurb={
            <>
              The two rates the platform charges itself. They apply to orders
              placed after you save and never reach backwards: what a customer
              was taxed is frozen on their order, and an invoice printed last
              week prints the same today. The fees are <strong>tax-inclusive</strong>
              {' '}&mdash; raising a rate changes how much of a{' '}
              {inr(settings.delivery.base_fee)} delivery fee is tax, not what the
              customer pays. Food is taxed per dish, below.
            </>
          }
          footer={
            <>
              <Button
                loading={busy === 'tax'}
                onClick={() =>
                  void save('tax', () =>
                    api.setTaxSettings(
                      tax.fee_gst_rate_bps,
                      tax.packaging_gst_rate_bps,
                    ),
                  )
                }
              >
                Save GST rates
              </Button>
              <Button
                variant="ghost"
                onClick={() => setTax(settings.tax)}
                disabled={busy !== null}
              >
                Reset
              </Button>
            </>
          }
        >
          <div className="space-y-4">
            <div className="grid gap-4 sm:grid-cols-2">
              <Select
                label="GST inside a service fee"
                value={String(tax.fee_gst_rate_bps)}
                onChange={(e) =>
                  setTax({ ...tax, fee_gst_rate_bps: Number(e.target.value) })
                }
                hint="Delivery, platform fee and the night and rain surcharge. 18% today."
              >
                {SLABS.map((bps) => (
                  <option key={bps} value={bps}>
                    {slabLabel(bps)}
                  </option>
                ))}
              </Select>
              <Select
                label="GST on packaging"
                value={String(tax.packaging_gst_rate_bps)}
                onChange={(e) =>
                  setTax({
                    ...tax,
                    packaging_gst_rate_bps: Number(e.target.value),
                  })
                }
                hint="Packaging is ancillary to the food it wraps, so it follows the food rate rather than the service rate. 5% today."
              >
                {SLABS.map((bps) => (
                  <option key={bps} value={bps}>
                    {slabLabel(bps)}
                  </option>
                ))}
              </Select>
            </div>

            {/* Not a third rate. Food is taxed at each dish's own slab, so the
                honest thing to show here is which slabs the live menu is
                actually on — and where to change one. */}
            <p className="text-sm text-ink-muted">
              <span className="font-medium text-ink">Food</span> is taxed per
              dish, not here.{' '}
              {tax.food_slabs_in_use.length === 0
                ? 'No dish is on sale right now, so no food slab is in use.'
                : `The menu on sale today sits on ${tax.food_slabs_in_use
                    .map((s) => `${slabLabel(s.rate_bps)} (${s.items} dish${s.items === 1 ? '' : 'es'})`)
                    .join(', ')}.`}{' '}
              Change one on the dish itself, in a{' '}
              <Link
                to="/restaurants"
                className="font-medium text-brand-ink underline"
              >
                restaurant's menu
              </Link>
              .
            </p>
          </div>
        </Section>

        {/* ------------------------------------------------------------- */}
        <Section
          title="Dispatch"
          blurb="How an order finds a rider. It rings one rider at a time, exclusively, then relays down the fleet; two riders reaching for the same order in the same instant are settled by who is closer. Changes apply to the next order offered, never to one already ringing."
          footer={
            <>
              <Button
                loading={busy === 'dispatch'}
                onClick={() =>
                  void save('dispatch', () => api.setDispatchSettings(dispatch))
                }
              >
                Save dispatch
              </Button>
              <Button
                variant="ghost"
                onClick={() => setDispatch(settings.dispatch)}
                disabled={busy !== null}
              >
                Reset
              </Button>
            </>
          }
        >
          <div className="grid gap-4 sm:grid-cols-2">
            <Field
              label="Seconds a rider has to answer"
              value={String(dispatch.offer_window_seconds)}
              onChange={num((v) => setDispatch({ ...dispatch, offer_window_seconds: v }))}
              hint="Their phone rings like a call for this long before it moves on."
            />
            <Field
              label="Contest window, seconds"
              value={String(dispatch.contest_seconds)}
              onChange={num((v) => setDispatch({ ...dispatch, contest_seconds: v }))}
              hint="Two riders accepting inside this window are settled by distance rather than by who tapped first."
            />
            <Field
              label="First search radius, km"
              value={String(dispatch.first_radius_km)}
              onChange={num((v) => setDispatch({ ...dispatch, first_radius_km: v }))}
              hint="How far out to look for a rider to begin with."
            />
            <Field
              label="Widen by, km"
              value={String(dispatch.radius_step_km)}
              onChange={num((v) => setDispatch({ ...dispatch, radius_step_km: v }))}
            />
            <Field
              label="Widen after, seconds"
              value={String(dispatch.widen_after_seconds)}
              onChange={num((v) => setDispatch({ ...dispatch, widen_after_seconds: v }))}
            />
            <Field
              label="Never look further than, km"
              value={String(dispatch.max_radius_km)}
              onChange={num((v) => setDispatch({ ...dispatch, max_radius_km: v }))}
            />
            <Field
              label="Jobs one rider may hold"
              value={String(dispatch.max_live_jobs)}
              onChange={num((v) => setDispatch({ ...dispatch, max_live_jobs: v }))}
              hint="Stacked runs. Raising this puts more food in one bag and more time between the first order and its door."
            />
            <Field
              label="Stack only within, km"
              value={String(dispatch.stack_drop_km)}
              onChange={num((v) => setDispatch({ ...dispatch, stack_drop_km: v }))}
              hint="Two drops further apart than this are never given to the same rider."
            />
          </div>
        </Section>

        {/* ------------------------------------------------------------- */}
        <Section
          title="Night and rain surcharge"
          blurb={
            <>
              Added to the delivery fee after dark and while it is raining. Two
              things worth remembering before changing either: the money rides in{' '}
              <code>surge_fee</code> and <strong>riders are paid none of it</strong>,
              and the rain half depends on a weather feed on a non-commercial
              licence. Whether it is raining right now is on{' '}
              <Link to="/settings/areas" className="font-medium text-brand-ink underline">
                Service areas
              </Link>
              .
            </>
          }
          footer={
            <>
              <Button
                loading={busy === 'surcharge'}
                onClick={() =>
                  void save('surcharge', () => api.setSurchargeSettings(surcharge))
                }
              >
                Save surcharges
              </Button>
              <Button
                variant="ghost"
                onClick={() => setSurcharge(settings.surcharge)}
                disabled={busy !== null}
              >
                Reset
              </Button>
            </>
          }
        >
          <div className="space-y-4">
            <Toggle
              label="Surcharges on"
              hint="Off means neither the night nor the rain amount is ever added, whatever the numbers below say."
              checked={surcharge.enabled}
              onChange={(v) => setSurcharge({ ...surcharge, enabled: v })}
            />
            <div className="grid gap-4 sm:grid-cols-2">
              <Field
                label="Night starts"
                type="time"
                value={surcharge.night_from.slice(0, 5)}
                onChange={(e) =>
                  setSurcharge({ ...surcharge, night_from: e.target.value })
                }
              />
              <Field
                label="Night ends"
                type="time"
                value={surcharge.night_to.slice(0, 5)}
                onChange={(e) =>
                  setSurcharge({ ...surcharge, night_to: e.target.value })
                }
              />
              <Field
                label="Night surcharge, rupees"
                value={String(surcharge.night_amount)}
                onChange={num((v) => setSurcharge({ ...surcharge, night_amount: v }))}
              />
              <Field
                label="Rain surcharge, rupees"
                value={String(surcharge.rain_amount)}
                onChange={num((v) => setSurcharge({ ...surcharge, rain_amount: v }))}
              />
              <Field
                label="Counts as rain at, mm"
                value={String(surcharge.rain_min_mm)}
                onChange={num((v) => setSurcharge({ ...surcharge, rain_min_mm: v }))}
                hint="Below this the feed's reading is treated as dry."
              />
              <Field
                label="Keep charging for, minutes"
                value={String(surcharge.rain_hold_minutes)}
                onChange={num((v) =>
                  setSurcharge({ ...surcharge, rain_hold_minutes: v }),
                )}
                hint="Roads stay wet after the rain stops, and the feed updates every five minutes."
              />
            </div>
            {!surcharge.has_weather_key && (
              <Banner tone="warn">
                No weather API key is set on this database, so the rain surcharge
                can never fire whatever it is set to. The night half is
                unaffected.
              </Banner>
            )}
          </div>
        </Section>

        {/* ------------------------------------------------------------- */}
        <Section
          title="Rider cash"
          blurb="How much uncollected cash-on-delivery a rider may be holding before they stop being offered cash orders."
        >
          <p className="text-sm text-ink">
            {inr(settings.cash.cap)} per rider ·{' '}
            <Link to="/cash" className="font-medium text-brand-ink underline">
              change it on Rider cash
            </Link>
            , where the ledger it applies to is.
          </p>
        </Section>
      </PageBody>

      {gate !== null && (
        <ConfirmDialog
          busy={busy === 'gate'}
          tone={gate ? 'default' : 'danger'}
          title={gate ? 'Turn payment verification back on?' : 'Turn payment verification OFF?'}
          body={
            gate
              ? 'Orders will again be refused unless Razorpay has confirmed the payment. Any order already placed is unaffected.'
              : 'Every new order will be accepted whether or not it was paid for, until somebody turns this back on. Do this only while verification itself is broken, and turn it back on the moment it is not.'
          }
          confirmLabel={gate ? 'Turn it on' : 'Turn it off'}
          onCancel={() => setGate(null)}
          onConfirm={() => {
            const next = gate
            setGate(null)
            void save('gate', () => api.setPaymentGate(next))
          }}
        />
      )}
    </>
  )
}
