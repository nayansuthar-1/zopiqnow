import type { MenuItemRow, RestaurantDetail } from '../lib/api'
import { todayLocal } from '../lib/dates'

/// What a restaurant still needs before it can be published.
///
/// **A mirror, not the rule.** `admin_publish_restaurant` (0030) holds the actual
/// conditions and re-checks every one of them server-side; this exists so an admin
/// can see what is left without pressing Publish and being told one thing at a
/// time. If the two ever disagree the database wins, and the sentence it raises is
/// shown verbatim.
///
/// **Its own module because two screens read it.** `ReviewStep` lists it, and the
/// wizard's step bar ticks a step when everything belonging to that step passes.
/// A second completeness rule written into the tab strip is exactly the divergence
/// the paragraph above warns about — there is one rule, and both callers get it
/// from here.
///
/// `step` is the index in the wizard's own `steps` array, which is what makes the
/// tab bar's grouping possible and what `ReviewStep`'s "Fix this" buttons jump to.

export type Check = { label: string; done: boolean; step: number; detail?: string }

export function checksFor(d: RestaurantDetail, menu: MenuItemRow[]): Check[] {
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
