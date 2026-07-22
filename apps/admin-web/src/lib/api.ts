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

/// A dish, as `admin_list_menu` returns it — including the rows a customer cannot
/// see. The world-readable policy is `is_available and category_available`, which
/// hides exactly what an editor most needs: the sold-out dish somebody has to
/// switch back on.
export type MenuItemRow = {
  id: string
  name: string
  description: string
  price: number
  is_veg: boolean
  is_bestseller: boolean
  image_url: string
  category: string
  category_rank: number
  item_rank: number
  is_available: boolean
  category_available: boolean
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

  listMenu: (id: string) => rpc<MenuItemRow[]>('admin_list_menu', { p_id: id }),

  upsertMenuItem: (id: string, item: Record<string, unknown>) =>
    rpc<string>('admin_upsert_menu_item', { p_id: id, p_item: item }),

  deleteMenuItem: (itemId: string) =>
    rpc<void>('admin_delete_menu_item', { p_item_id: itemId }),

  /// The menu's whole running order, not just the rows that moved — ranks are only
  /// meaningful relative to each other, and dragging one dish renumbers everything
  /// under it.
  reorderMenu: (
    id: string,
    order: { id: string; category: string; category_rank: number; item_rank: number }[],
  ) => rpc<void>('admin_reorder_menu', { p_id: id, p_order: order }),

  renameCategory: (id: string, from: string, to: string) =>
    rpc<void>('admin_rename_category', { p_id: id, p_from: from, p_to: to }),

  setCategoryAvailable: (id: string, category: string, available: boolean) =>
    rpc<void>('admin_set_category_available', {
      p_id: id,
      p_category: category,
      p_available: available,
    }),

  unpublishRestaurant: (id: string) =>
    rpc<void>('admin_unpublish_restaurant', { p_id: id }),

  publishRestaurant: (id: string) =>
    rpc<void>('admin_publish_restaurant', { p_id: id }),

  listRiders: () => rpc<RiderRow[]>('admin_list_riders'),

  addRider: (email: string, name: string, phone: string, vehicle: Vehicle) =>
    rpc<void>('admin_add_rider', {
      p_email: email,
      p_name: name,
      p_phone: phone,
      p_vehicle: vehicle,
    }),

  /// No email here to change — it is the primary key, and the address a rider
  /// signs in with. Editing it would not rename anyone, it would orphan every
  /// delivery they have made.
  updateRider: (email: string, name: string, phone: string, vehicle: Vehicle) =>
    rpc<void>('admin_update_rider', {
      p_email: email,
      p_name: name,
      p_phone: phone,
      p_vehicle: vehicle,
    }),

  /// Refused by the database while the rider is carrying an order — deactivating
  /// them mid-delivery would leave it undeliverable by anyone. The message says
  /// which order, and this layer passes it through.
  setRiderActive: (email: string, active: boolean) =>
    rpc<void>('admin_set_rider_active', { p_email: email, p_active: active }),

  listAdmins: () => rpc<AdminRow[]>('admin_list_admins'),

  addAdmin: (email: string, name: string) =>
    rpc<void>('admin_add_admin', { p_email: email, p_name: name }),

  removeAdmin: (email: string) => rpc<void>('admin_remove_admin', { p_email: email }),
}

export type AdminRow = { email: string; name: string; created_at: string }

/// The three vehicles `delivery_partners.vehicle` allows.
export type Vehicle = 'bike' | 'scooter' | 'bicycle'

/// A delivery partner, as the roster shows them. `live_order_id` is the order
/// they are carrying right now — the reason the console can grey out the switch
/// *and* say why, rather than letting the database refuse after the click.
export type RiderRow = {
  email: string
  name: string
  phone: string
  vehicle: Vehicle
  is_active: boolean
  created_at: string
  live_order_id: string | null
  delivered_count: number
}
