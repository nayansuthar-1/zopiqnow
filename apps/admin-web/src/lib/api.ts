import { supabase, messageFor } from './supabase'

/// Every call the console makes, in one file.
///
/// All of them are RPCs, because none of these tables grant a write to the
/// browser and half of them do not grant a read either — a draft restaurant and a
/// sold-out dish are both invisible through PostgREST, even to an admin. The
/// functions are `security definer` and check `is_admin()` themselves, so what
/// follows is a transport layer and nothing more: there is no rule enforced here
/// that is not also enforced in the database.

export type RestaurantRow = {
  id: string
  name: string
  city: string | null
  is_active: boolean
  accepting_orders: boolean
  image_url: string
  menu_item_count: number
  owner_email: string | null
  published_at: string | null
  created_at: string
}

/// What the pill says. Derived, never stored — `is_active` and `published_at`
/// between them already answer it, and a status column would be a third thing
/// that could disagree with those two.
export type Status = 'live' | 'paused' | 'draft' | 'delisted'

export function statusOf(r: RestaurantRow): Status {
  if (r.is_active) return r.accepting_orders ? 'live' : 'paused'
  return r.published_at ? 'delisted' : 'draft'
}

/// Raised for anything the database refused. Its message is the sentence the RPC
/// wrote — those are meant to be read by a person and are shown unaltered.
export class ApiError extends Error {}

async function rpc<T>(fn: string, params?: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.rpc(fn, params)
  if (error) throw new ApiError(messageFor(error))
  return data as T
}

/// The shape `admin_get_restaurant` returns. `bank` never carries the account
/// number — only its last four digits — so there is no field here to leak one.
export type RestaurantDetail = {
  restaurant: {
    id: string
    name: string
    cuisines: string[]
    price_for_two: number
    eta_minutes: number
    is_veg: boolean
    promo_text: string | null
    image_url: string
    owner_name: string | null
    contact_phone: string | null
    address_line: string | null
    city: string | null
    state: string | null
    pincode: string | null
    latitude: number | null
    longitude: number | null
    commission_bps: number
    is_active: boolean
    published_at: string | null
    rating: number
    rating_count: number
  }
  legal: {
    fssai_number: string | null
    fssai_expiry: string | null
    fssai_doc_path: string | null
    gst_number: string | null
    pan_number: string | null
    pan_doc_path: string | null
  } | null
  bank: {
    account_holder: string | null
    account_last4: string | null
    ifsc: string | null
    bank_name: string | null
    verified: boolean
  } | null
  hours: { day: number; opens: string; closes: string }[]
  staff: { email: string; role: 'owner' | 'staff' }[]
}

export const api = {
  listRestaurants: () => rpc<RestaurantRow[]>('admin_list_restaurants'),

  getRestaurant: (id: string) =>
    rpc<RestaurantDetail>('admin_get_restaurant', { p_id: id }),

  createRestaurant: (profile: Record<string, unknown>) =>
    rpc<string>('admin_create_restaurant', { p_profile: profile }),

  /// Only the keys present are written — that is the contract of the RPC, not a
  /// convenience here. Sending a subset is how a wizard step saves its own four
  /// fields without resending, and possibly clobbering, the other twelve.
  updateRestaurant: (id: string, profile: Record<string, unknown>) =>
    rpc<void>('admin_update_restaurant', { p_id: id, p_profile: profile }),

  setLegal: (id: string, legal: Record<string, unknown>) =>
    rpc<void>('admin_set_legal', { p_id: id, p_legal: legal }),

  setBank: (id: string, bank: Record<string, unknown>) =>
    rpc<void>('admin_set_bank', { p_id: id, p_bank: bank }),

  /// The whole week, every time. A schedule saved a day at a time is how a
  /// Tuesday gets left behind, so the RPC deletes and reinserts.
  setHours: (id: string, hours: { day: number; opens: string; closes: string }[]) =>
    rpc<void>('admin_set_hours', { p_id: id, p_hours: hours }),

  addStaff: (id: string, email: string, role: 'owner' | 'staff') =>
    rpc<void>('admin_add_staff', { p_id: id, p_email: email, p_role: role }),

  setStaffRole: (id: string, email: string, role: 'owner' | 'staff') =>
    rpc<void>('admin_set_staff_role', { p_id: id, p_email: email, p_role: role }),

  removeStaff: (id: string, email: string) =>
    rpc<void>('admin_remove_staff', { p_id: id, p_email: email }),

  unpublishRestaurant: (id: string) =>
    rpc<void>('admin_unpublish_restaurant', { p_id: id }),

  publishRestaurant: (id: string) =>
    rpc<void>('admin_publish_restaurant', { p_id: id }),
}
