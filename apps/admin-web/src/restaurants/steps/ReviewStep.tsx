import { useEffect, useState } from 'react'
import { api } from '../../lib/api'
import type { MenuItemRow, RestaurantDetail } from '../../lib/api'
import { todayLocal } from '../../lib/dates'
import {
  Button,
  Card,
  ConfirmDialog,
  Modal,
  TextArea,
} from '../../ui/primitives'

/// Everything collected, in one place, with what is still missing said plainly.
///
/// The checklist below is a **mirror**, not the rule. `admin_publish_restaurant`
/// (0030) holds the actual conditions and re-checks every one of them server-side;
/// this exists so an admin can see what is left without pressing Publish and being
/// told one thing at a time. If the two ever disagree the database wins, and the
/// sentence it raises is shown verbatim.

type Check = { label: string; done: boolean; step: number; detail?: string }

function checksFor(d: RestaurantDetail, menu: MenuItemRow[]): Check[] {
  const r = d.restaurant
  const sellable = menu.filter((m) => m.is_available && m.category_available)
  const expiry = d.legal?.fssai_expiry
  const expired = expiry ? expiry < todayLocal() : false

  return [
    {
      label: 'Cover photo',
      done: Boolean(r.image_url),
      step: 0,
    },
    {
      label: 'Full address',
      done: Boolean(r.address_line && r.city && r.pincode),
      step: 1,
      detail: [r.address_line, r.city, r.pincode].filter(Boolean).join(', '),
    },
    {
      label: 'Contact phone',
      done: Boolean(r.contact_phone),
      step: 1,
      detail: r.contact_phone ?? undefined,
    },
    {
      label: 'FSSAI licence',
      done: Boolean(d.legal?.fssai_number) && Boolean(expiry) && !expired,
      step: 2,
      detail: expired
        ? `Expired ${expiry}`
        : d.legal?.fssai_number
          ? `${d.legal.fssai_number}${expiry ? ` · expires ${expiry}` : ' · no expiry set'}`
          : undefined,
    },
    {
      label: 'PAN',
      done: Boolean(d.legal?.pan_number),
      step: 2,
      detail: d.legal?.pan_number ?? undefined,
    },
    {
      label: 'Bank account',
      done: Boolean(d.bank?.account_last4 && d.bank?.ifsc),
      step: 3,
      detail: d.bank?.account_last4
        ? `Ends ${d.bank.account_last4} · ${d.bank.ifsc ?? 'no IFSC'}`
        : undefined,
    },
    {
      label: 'Opening hours',
      done: d.hours.length > 0,
      step: 4,
      detail: d.hours.length ? `${d.hours.length} days set` : undefined,
    },
    {
      label: 'An owner who can run it',
      done: d.staff.some((s) => s.role === 'owner'),
      step: 5,
      detail: d.staff.find((s) => s.role === 'owner')?.email,
    },
    {
      label: 'At least one dish customers can order',
      done: sellable.length > 0,
      step: 6,
      detail: menu.length
        ? `${sellable.length} of ${menu.length} available`
        : undefined,
    },
  ]
}

export function ReviewStep({
  id,
  detail,
  onSaved,
  onGoToStep,
}: {
  id: string
  detail: RestaurantDetail | null
  onSaved: () => Promise<void>
  onGoToStep: (step: number) => void
}) {
  const [menu, setMenu] = useState<MenuItemRow[] | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [published, setPublished] = useState(false)
  const [confirming, setConfirming] = useState(false)
  const [forcing, setForcing] = useState(false)
  const [reason, setReason] = useState('')

  useEffect(() => {
    api
      .listMenu(id)
      .then(setMenu)
      .catch((e) => setError(e instanceof Error ? e.message : String(e)))
  }, [id])

  if (!detail || menu === null) {
    return <p className="text-sm text-ink-muted">Loading…</p>
  }

  const r = detail.restaurant
  const checks = checksFor(detail, menu)
  const outstanding = checks.filter((c) => !c.done)

  async function publish(force = false) {
    setBusy(true)
    setError(null)
    try {
      await api.publishRestaurant(id, force, force ? reason : undefined)
      await onSaved()
      setConfirming(false)
      setForcing(false)
      setPublished(true)
    } catch (e) {
      // The gate's own sentence — "Add at least one dish before publishing." —
      // shown as written. It knows more than the checklist above does.
      setError(e instanceof Error ? e.message : String(e))
      setConfirming(false)
      setForcing(false)
    } finally {
      setBusy(false)
    }
  }

  async function unpublish() {
    setBusy(true)
    setError(null)
    try {
      await api.unpublishRestaurant(id)
      await onSaved()
      setPublished(false)
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="space-y-5">
      <Card>
        <h2 className="text-base font-bold text-ink">Before it goes live</h2>
        <p className="mt-1 text-sm text-ink-muted">
          {outstanding.length === 0
            ? 'Everything needed is in place.'
            : `${outstanding.length} ${
                outstanding.length === 1 ? 'thing is' : 'things are'
              } still missing.`}
        </p>

        <ul className="mt-5 divide-y divide-line">
          {checks.map((c) => (
            <li key={c.label} className="flex items-center gap-3 py-2.5">
              <span
                className={`flex h-5 w-5 shrink-0 items-center justify-center rounded-full text-xs font-bold ${
                  c.done ? 'bg-veg-soft text-veg' : 'bg-non-veg-soft text-non-veg-ink'
                }`}
                aria-hidden
              >
                {c.done ? '✓' : '!'}
              </span>
              <span className="flex-1 text-sm text-ink">
                {c.label}
                {c.detail && (
                  <span className="ml-2 text-ink-muted">{c.detail}</span>
                )}
              </span>
              {!c.done && (
                <button
                  type="button"
                  onClick={() => onGoToStep(c.step)}
                  className="text-sm font-semibold text-brand-ink hover:text-ink"
                >
                  Fix
                </button>
              )}
            </li>
          ))}
        </ul>
      </Card>

      <Card>
        <h2 className="text-base font-bold text-ink">Storefront</h2>
        <dl className="mt-4 grid gap-x-6 gap-y-3 sm:grid-cols-2">
          {[
            ['Name', r.name],
            ['Cuisines', r.cuisines.join(', ') || '—'],
            // Cost for two is still gone (0101) — nobody is asked for it, so
            // reviewing it would be reviewing a number nobody entered. Prep
            // time is asked for again (0134) and reaches the customer feed, so
            // it belongs in front of whoever is about to publish.
            ['Prep time', `${r.eta_minutes} min`],
            ['Pure veg', r.is_veg ? 'Yes' : 'No'],
            ['Offer line', r.promo_text ?? '—'],
            ['Commission', `${r.commission_bps / 100}%`],
            ['Owner', r.owner_name ?? '—'],
          ].map(([label, value]) => (
            <div key={label}>
              <dt className="text-xs uppercase tracking-wide text-ink-muted">{label}</dt>
              <dd className="text-sm text-ink">{value}</dd>
            </div>
          ))}
        </dl>
      </Card>

      {published || r.is_active ? (
        <div className="rounded-card border border-veg bg-veg-soft p-6">
          <h2 className="text-base font-bold text-veg">This restaurant is live</h2>
          <p className="mt-1 text-sm text-ink">
            Customers can see and order from it in the app now. Edits from here take
            effect immediately.
          </p>
          <Button
            variant="secondary"
            className="mt-4"
            loading={busy}
            onClick={() => void unpublish()}
          >
            Take it off the platform
          </Button>
        </div>
      ) : (
        <Card>
          <h2 className="text-base font-bold text-ink">Publish</h2>
          <p className="mt-1 text-sm text-ink-muted">
            This puts the restaurant in front of every customer on Zopiqnow.
          </p>
          <div className="mt-4 flex flex-wrap items-center gap-3">
            <Button
              disabled={outstanding.length > 0}
              onClick={() => setConfirming(true)}
            >
              Publish restaurant
            </Button>
            {outstanding.length > 0 && (
              // The override. Deliberately the quieter of the two buttons, and
              // deliberately not the one that looks like the way forward.
              <Button variant="secondary" onClick={() => setForcing(true)}>
                Publish anyway
              </Button>
            )}
          </div>
          {outstanding.length > 0 && (
            <p className="mt-2 text-sm text-ink-muted">
              Finish the {outstanding.length} outstanding{' '}
              {outstanding.length === 1 ? 'item' : 'items'} above, or publish anyway
              and finish them later. Publishing anyway is recorded against your name
              with what was missing.
            </p>
          )}
        </Card>
      )}

      {error && (
        <p className="rounded-field bg-non-veg-soft px-4 py-3 text-sm text-non-veg-ink">
          {error}
        </p>
      )}

      {confirming && (
        <ConfirmDialog
          title={`Publish ${r.name}?`}
          body="It appears in the customer app straight away and can start taking orders. You can take it off again at any time."
          confirmLabel="Publish"
          busy={busy}
          onCancel={() => setConfirming(false)}
          onConfirm={() => void publish()}
        />
      )}

      {forcing && (
        <Modal
          title={`Publish ${r.name} without finishing it?`}
          busy={busy}
          onClose={() => setForcing(false)}
          footer={
            <>
              <Button
                variant="secondary"
                onClick={() => setForcing(false)}
                disabled={busy}
              >
                Cancel
              </Button>
              <Button variant="danger" loading={busy} onClick={() => void publish(true)}>
                Publish anyway
              </Button>
            </>
          }
        >
          <div className="space-y-4">
            <p className="text-sm text-ink-muted">
              It goes in front of every customer straight away with{' '}
              {outstanding.length === 1 ? 'this still missing' : 'these still missing'}:
            </p>
            <ul className="list-disc space-y-1 pl-5 text-sm text-ink">
              {outstanding.map((c) => (
                <li key={c.label}>{c.label}</li>
              ))}
            </ul>

            {/* Named rather than left to the general warning, because these two
                are the ones with a consequence outside the console. */}
            {!checks.find((c) => c.label.startsWith('At least one dish'))?.done && (
              <p className="rounded-field bg-non-veg-soft px-4 py-3 text-sm text-non-veg-ink">
                With no orderable dish, a customer who opens this restaurant sees an
                empty menu — which reads as a broken app rather than as a kitchen
                that has not finished onboarding.
              </p>
            )}
            {!checks.find((c) => c.label === 'FSSAI licence')?.done && (
              <p className="rounded-field bg-non-veg-soft px-4 py-3 text-sm text-non-veg-ink">
                Listing a kitchen with no valid FSSAI licence on file is a legal
                exposure for the platform, not just an incomplete record.
              </p>
            )}

            <TextArea
              label="Why (optional)"
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              placeholder="Owner opens today; licence is with the FSSAI office."
              hint="Recorded against your name in the audit trail, with the list above."
              rows={2}
            />
          </div>
        </Modal>
      )}
    </div>
  )
}
