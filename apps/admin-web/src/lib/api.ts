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

  /// Only ever succeeds for a delisted restaurant that has never taken an order
  /// (migration 0044). The refusal names which of the two rules stopped it.
  deleteRestaurant: (id: string) =>
    rpc<void>('admin_delete_restaurant', { p_id: id }),

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

  getRiderPayRates: () => rpc<RiderPayRates[]>('admin_get_rider_pay_rates'),

  listRiderPayouts: (status?: 'pending' | 'paid') =>
    rpc<RiderPayoutRow[]>('admin_list_rider_payouts', { p_status: status ?? null }),

  markRiderPayoutPaid: (id: number, reference: string) =>
    rpc<void>('admin_mark_rider_payout_paid', { p_id: id, p_reference: reference }),

  getRiderBank: (email: string) =>
    rpc<RiderBank[]>('admin_get_rider_bank', { p_email: email }),

  setRiderBank: (email: string, bank: Record<string, unknown>) =>
    rpc<void>('admin_set_rider_bank', { p_email: email, p_bank: bank }),

  setRiderPayRates: (baseFee: number, perKmFee: number) =>
    rpc<void>('admin_set_rider_pay_rates', {
      p_base_fee: baseFee,
      p_per_km_fee: perKmFee,
    }),

  /// Every slide, including the ones no customer can see. The table's own read
  /// policy shows only what is live right now, which is exactly the wrong thing
  /// for an editor — the row you go looking for is usually the expired one.
  listHeroSlides: () => rpc<HeroSlideRow[]>('admin_list_hero_slides'),

  /// Create (no `id`) or edit (with one). Every field, every time: a hero slide
  /// is one short form with no steps, so there is nothing to save a quarter of.
  /// `is_active` is deliberately not among them — publishing is its own action
  /// below, so fixing a typo cannot put a slide on screen by accident.
  upsertHeroSlide: (slide: Record<string, unknown>) =>
    rpc<string>('admin_upsert_hero_slide', { p_slide: slide }),

  /// Re-checks the slide's destination on the way up: a restaurant it points at
  /// may have been delisted since it was written, and this is the last look
  /// anybody takes before it reaches a home screen.
  setHeroSlideActive: (id: string, active: boolean) =>
    rpc<void>('admin_set_hero_slide_active', { p_id: id, p_active: active }),

  /// A real delete, unlike a restaurant or a rider — nothing hangs off a slide.
  deleteHeroSlide: (id: string) =>
    rpc<void>('admin_delete_hero_slide', { p_id: id }),

  /// No argument is the live board — every order that has not ended. An argument
  /// is a lookup by order id or phone across every status, because the order
  /// support gets called about is usually one that already ended badly.
  orders: (query?: string) =>
    rpc<AdminOrderRow[]>('admin_orders', { p_query: query ?? null }),

  /// Takes the order off its rider and puts it back in the dispatcher's way.
  /// The order survives. Returns whoever was holding it.
  releaseDelivery: (orderId: string, reason: string) =>
    rpc<string>('admin_release_delivery', {
      p_order_id: orderId,
      p_reason: reason,
    }),

  /// Ends the order at any live status. Refused once delivered — that one has an
  /// invoice behind it and is a refund, not an erasure.
  cancelOrder: (orderId: string, reason: string) =>
    rpc<string>('admin_cancel_order', { p_order_id: orderId, p_reason: reason }),

  /// The whole order book, not just what is open. Every filter is optional and
  /// omitting one means "don't narrow by it"; the row carries `total_count`, the
  /// size of the full match, so the pager knows whether there is more.
  allOrders: (f: {
    query?: string
    status?: OrderStatus | null
    restaurantId?: string | null
    from?: string | null
    to?: string | null
    limit?: number
    offset?: number
  }) =>
    rpc<AllOrderRow[]>('admin_all_orders', {
      p_query: f.query?.trim() ? f.query.trim() : null,
      p_status: f.status ?? null,
      p_restaurant_id: f.restaurantId ?? null,
      p_from: f.from ?? null,
      p_to: f.to ?? null,
      p_limit: f.limit ?? 50,
      p_offset: f.offset ?? 0,
    }),

  /// **Destroys the order.** Not a status change and not an archive: the row is
  /// gone, and seven cascades take its items, its delivery, its messages and the
  /// customer's review with it. There is no status it refuses — a delivered,
  /// invoiced order deletes like any other, which is the operator's stated
  /// decision and which puts a permanent gap in that restaurant's GST invoice
  /// series. Returns a sentence naming what was destroyed.
  ///
  /// Every call writes an `admin_order_deletions` row first, in the same
  /// transaction. That is the only thing that survives.
  deleteOrder: (orderId: string, reason: string) =>
    rpc<string>('admin_delete_order', { p_order_id: orderId, p_reason: reason }),

  /// What has been deleted, newest first. The one way back to an order that no
  /// longer exists.
  orderDeletions: (limit = 100) =>
    rpc<OrderDeletionRow[]>('admin_list_order_deletions', { p_limit: limit }),

  listCoupons: () => rpc<CouponRow[]>('admin_list_coupons'),

  /// Platform coupons only — it writes `restaurant_id = null` and refuses a code
  /// in a restaurant's reserved `<id>-…` namespace.
  saveCoupon: (c: {
    code: string
    min_subtotal: number
    flat_off: number | null
    percent_off: number | null
    max_off: number | null
    valid_until: string | null
  }) =>
    rpc<string>('admin_save_coupon', {
      p_code: c.code,
      p_min_subtotal: c.min_subtotal,
      p_flat_off: c.flat_off,
      p_percent_off: c.percent_off,
      p_max_off: c.max_off,
      p_valid_until: c.valid_until,
    }),

  /// A restaurant's own code can be switched off from here, and only off.
  setCouponActive: (code: string, active: boolean) =>
    rpc<void>('admin_set_coupon_active', { p_code: code, p_active: active }),

  /// Only ever succeeds for a platform code no order has carried.
  deleteCoupon: (code: string) =>
    rpc<void>('admin_delete_coupon', { p_code: code }),

  broadcastReach: (audience: Audience) =>
    rpc<number>('admin_broadcast_reach', { p_audience: audience }),

  sendBroadcast: (audience: Audience, title: string, body: string) =>
    rpc<number>('admin_send_broadcast', {
      p_audience: audience,
      p_title: title,
      p_body: body,
    }),

  listBroadcasts: () => rpc<BroadcastRow[]>('admin_list_broadcasts'),

  /// Returns a table of exactly one row, like the pay rates do.
  platformStats: (days: number) =>
    rpc<PlatformStats[]>('admin_platform_stats', { p_days: days }),

  dailyOrders: (days: number) =>
    rpc<DailyOrders[]>('admin_daily_orders', { p_days: days }),

  topRestaurants: (days: number, limit = 10) =>
    rpc<TopRestaurant[]>('admin_top_restaurants', {
      p_days: days,
      p_limit: limit,
    }),

  listSettlements: (status?: 'pending' | 'paid') =>
    rpc<SettlementRow[]>('admin_list_settlements', { p_status: status ?? null }),

  markSettlementPaid: (id: number, reference: string) =>
    rpc<void>('admin_mark_settlement_paid', { p_id: id, p_reference: reference }),

  /// The full account number, for whoever is making the transfer.
  /// `getRestaurant` returns the last four and will keep returning the last four.
  getRestaurantBank: (id: string) =>
    rpc<RestaurantBank[]>('admin_get_restaurant_bank', { p_id: id }),
}

/// The three audiences a `notifications` row can be addressed to.
export type Audience = 'customer' | 'rider' | 'restaurant'

/// One order on the live board, or one search hit. Everything a support call
/// needs is on the row — the kitchen, the rider, the offer in flight, the ETA
/// and the sentence explaining it — so answering "where is my food" is one
/// round trip. The delivery *codes* are deliberately absent: 0049 put those
/// beyond every read but one function per identity, and an admin is not one of
/// those identities.
export type AdminOrderRow = {
  order_id: string
  restaurant_id: string
  restaurant_name: string
  status: OrderStatus
  status_reason: string | null
  placed_at: string
  accept_deadline: string
  ready_by: string | null
  eta_at: string | null
  eta_reason: string | null
  total: number
  payment_method: 'cod' | 'upi'
  coupon_code: string | null
  delivery_to: string
  customer_phone: string
  route_km: number | null
  rider_email: string | null
  rider_name: string | null
  rider_phone: string | null
  rider_vehicle: Vehicle | null
  delivery_state: DeliveryState | null
  claimed_at: string | null
  /// A rider currently deciding on this order. Mutually exclusive with a rider
  /// holding it — the dispatcher will not offer an order that has a delivery.
  offer_to: string | null
  offer_expires_at: string | null
}

/// One order in the whole-book view. Deliberately narrower than
/// [AdminOrderRow]: this screen is a ledger, not a support console, so it drops
/// the live machinery (accept deadline, the offer in flight, the ETA and its
/// reason) and adds the two things only history cares about — the invoice number
/// and how many lines were on the order.
export type AllOrderRow = {
  order_id: string
  restaurant_id: string
  restaurant_name: string
  status: OrderStatus
  status_reason: string | null
  placed_at: string
  total: number
  payment_method: 'cod' | 'upi'
  coupon_code: string | null
  delivery_to: string
  customer_phone: string
  route_km: number | null
  /// Issued on delivery (0063). Null for every order that never got there.
  invoice_no: string | null
  rider_name: string | null
  rider_phone: string | null
  delivery_state: DeliveryState | null
  item_count: number
  /// The size of the full match, repeated on every row — the pager reads it.
  total_count: number
}

/// A deletion that happened. The order it names does not exist any more; this
/// row and its jsonb snapshot are what is left.
export type OrderDeletionRow = {
  order_id: string
  restaurant_id: string
  deleted_by: string
  deleted_at: string
  reason: string
  order_status: OrderStatus
  invoice_no: string | null
  total: number | null
}

export type OrderStatus =
  | 'placed'
  | 'accepted'
  | 'preparing'
  | 'ready_for_pickup'
  | 'out_for_delivery'
  | 'delivered'
  | 'rejected'
  | 'cancelled'

export type DeliveryState =
  | 'claimed'
  | 'arrived_at_restaurant'
  | 'picked_up'
  | 'arrived_at_customer'
  | 'delivered'
  | 'cancelled'

/// What the board calls each status. The wire values are the database's and are
/// never shown raw — `ready_for_pickup` is not a sentence anybody says.
export const STATUS_LABEL: Record<OrderStatus, string> = {
  placed: 'Awaiting accept',
  accepted: 'Accepted',
  preparing: 'Cooking',
  ready_for_pickup: 'On the shelf',
  out_for_delivery: 'On the way',
  delivered: 'Delivered',
  rejected: 'Rejected',
  cancelled: 'Cancelled',
}

export const DELIVERY_LABEL: Record<DeliveryState, string> = {
  claimed: 'heading to the kitchen',
  arrived_at_restaurant: 'at the counter',
  picked_up: 'carrying',
  arrived_at_customer: 'at the door',
  delivered: 'delivered',
  cancelled: 'released',
}

/// A coupon as the console lists it. `restaurant_id` null is a platform code —
/// the only kind this screen can create or edit. A restaurant's own offer is
/// here to be *seen* (and, if it has to be, switched off), which is what makes
/// "why was this order ₹200 off" answerable.
export type CouponRow = {
  code: string
  restaurant_id: string | null
  restaurant_name: string | null
  min_subtotal: number
  flat_off: number | null
  percent_off: number | null
  max_off: number | null
  valid_until: string | null
  is_active: boolean
  created_at: string
  redeemed: number
  discount_given: number
}

/// What a coupon is doing right now — the same three fields `validate_coupon`
/// reads, so the pill and the checkout can never disagree.
export type CouponState = 'live' | 'off' | 'expired'

export function couponStateOf(c: CouponRow, now = Date.now()): CouponState {
  if (c.valid_until && Date.parse(c.valid_until) <= now) return 'expired'
  return c.is_active ? 'live' : 'off'
}

/// One message sent to everybody in an audience. The row exists so a broadcast
/// leaves a mark: it is the most public thing this console can do and it has no
/// undo.
export type BroadcastRow = {
  id: number
  audience: Audience
  title: string
  body: string | null
  recipient_count: number
  sent_by: string
  created_at: string
}

/// The platform's own numbers, derived on every call. There is no rollup table
/// and there should not be one at this volume — a stored figure is a figure that
/// can be wrong.
export type PlatformStats = {
  days: number
  orders_placed: number
  orders_delivered: number
  orders_cancelled: number
  orders_rejected: number
  /// Delivered orders only. A placed-then-cancelled order is not revenue.
  gmv: number
  /// The platform's cut, on `subtotal` — never on tax or the delivery fee.
  commission: number
  discount_given: number
  avg_order: number
  live_orders: number
  restaurants_live: number
  riders_active: number
  riders_carrying: number
  customers_ordering: number
}

export type DailyOrders = {
  day: string
  placed: number
  delivered: number
  cancelled: number
  gmv: number
}

export type TopRestaurant = {
  restaurant_id: string
  name: string
  orders: number
  gmv: number
  rating: number
  rating_count: number
}

/// One week's trade for one restaurant (migration 0017), rolled up every Monday
/// by `run_settlement_batch`. Nothing in the console creates one.
export type SettlementRow = {
  id: number
  restaurant_id: string
  restaurant_name: string
  period_start: string
  period_end: string
  order_count: number
  gross_sales: number
  commission: number
  net_payable: number
  status: 'pending' | 'paid'
  reference: string | null
  has_bank: boolean
  paid_at: string | null
}

export type RestaurantBank = {
  account_holder: string | null
  account_number: string | null
  ifsc: string | null
  bank_name: string | null
  verified: boolean
  updated_at: string
}

/// One campaign slide on the customer home hero (migration 0053).
///
/// `cta_target` null is the ordinary case rather than a gap: it means the
/// button scrolls the customer's home feed down to the restaurant list, which is
/// what the hero's button has always done.
export type HeroSlideRow = {
  id: string
  title: string
  subtitle: string
  cta_label: string
  cta_target: string | null
  image_url: string
  /// The looping animated WebP over the still (0054). Null is the ordinary
  /// case — most slides are a photograph — and the still is what shows when it
  /// is absent, still downloading, or the phone has asked for reduced motion.
  motion_url: string | null
  sort_order: number
  is_active: boolean
  starts_at: string
  ends_at: string | null
  created_at: string
}

/// What a slide is doing right now. Derived from the same three fields the read
/// policy uses, so the pill and the customer's phone can never disagree.
export type SlideState = 'live' | 'off' | 'scheduled' | 'expired'

export function slideStateOf(s: HeroSlideRow, now = Date.now()): SlideState {
  if (s.ends_at && Date.parse(s.ends_at) <= now) return 'expired'
  if (!s.is_active) return 'off'
  if (Date.parse(s.starts_at) > now) return 'scheduled'
  return 'live'
}

export type AdminRow = { email: string; name: string; created_at: string }

/// What a delivery pays a rider (migration 0043). One row, platform-wide — the
/// RPC returns a table, so this arrives as an array of exactly one.
/// One week's pay for one rider (migration 0045). `has_bank` rather than the
/// account number: a payout list is read at a glance and over shoulders, and the
/// number is only needed by whoever is actually making the transfer.
export type RiderPayoutRow = {
  id: number
  partner_email: string
  partner_name: string
  period_start: string
  period_end: string
  delivery_count: number
  amount: number
  status: 'pending' | 'paid'
  reference: string | null
  has_bank: boolean
  paid_at: string | null
}

export type RiderBank = {
  account_holder: string | null
  account_number: string | null
  ifsc: string | null
  bank_name: string | null
  verified: boolean
  updated_at: string
}

export type RiderPayRates = {
  base_fee: number
  per_km_fee: number
  updated_at: string
}

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
