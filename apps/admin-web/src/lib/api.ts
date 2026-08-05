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

  /// The optional half (0068, 0078 — reachable from the console since 0108).
  /// Every one of these is null when the restaurant has not said, which is the
  /// normal case and not a gap to be filled in.
  ///
  /// `serve_from`/`serve_to` arrive as `HH:MM` rather than a time, because the
  /// only thing that reads them is an `<input type="time">`, which speaks
  /// exactly that.
  original_price: number | null
  prep_minutes: number | null
  serve_from: string | null
  serve_to: string | null
  /// Why a dish is off. Kitchen-facing — a customer never reads it, because RLS
  /// has already removed the dish it would have appeared on.
  unavailable_reason: string
  gst_rate_bps: number
  hsn_code: string | null
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

  /// Deletes a whole section — every dish in it. Refused outright if any one of
  /// them appears on a past order (migration 0107); nothing is half-deleted.
  /// Returns how many dishes went.
  deleteCategory: (id: string, category: string) =>
    rpc<number>('admin_delete_category', { p_id: id, p_category: category }),

  /// Deletes every dish on the restaurant's menu, under the same all-or-nothing
  /// rule as a section.
  deleteMenu: (id: string) => rpc<number>('admin_delete_menu', { p_id: id }),

  unpublishRestaurant: (id: string) =>
    rpc<void>('admin_unpublish_restaurant', { p_id: id }),

  /// Publishes, or refuses with the first thing that is missing.
  ///
  /// `force` (migration 0105) publishes anyway — the admin's judgement over the
  /// checklist — and writes a row to the audit trail naming every check that was
  /// outstanding at the moment it went live, plus [reason]. There is no way to
  /// force one quietly, which is the point.
  publishRestaurant: (id: string, force = false, reason?: string) =>
    rpc<void>('admin_publish_restaurant', {
      p_id: id,
      p_force: force,
      p_reason: reason ?? null,
    }),

  /// Only ever succeeds for a delisted restaurant that has never taken an order
  /// (migration 0044). The refusal names which of the two rules stopped it.
  deleteRestaurant: (id: string) =>
    rpc<void>('admin_delete_restaurant', { p_id: id }),

  /// Everybody who has ever signed in, whatever they signed in *to*.
  ///
  /// One list rather than one per app, because the roles are not exclusive and a
  /// per-app list would show the same person three times without saying so.
  listUsers: () => rpc<UserRow[]>('admin_list_users'),

  getUser: (userId: string) =>
    rpc<UserDetail>('admin_get_user', { p_user_id: userId }),

  userOrders: (userId: string) =>
    rpc<UserOrder[]>('admin_user_orders', { p_user_id: userId }),

  /// Blocking sets `auth.users.banned_until` and drops the person's sessions, so
  /// it survives a reinstall and does not wait for a token to expire. The
  /// database refuses to block an admin, or you — see migration 0088.
  setUserBlocked: (userId: string, blocked: boolean, reason?: string) =>
    rpc<void>('admin_set_user_blocked', {
      p_user_id: userId,
      p_blocked: blocked,
      p_reason: reason ?? null,
    }),

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

  getRiderKyc: (email: string) =>
    rpc<RiderKyc[]>('admin_get_rider_kyc', { p_email: email }),

  /// Saving anything here sends the rider back to `pending`, including a typo
  /// fix. Deliberate (0080): "verified" has to mean that what is on file *now*
  /// was read by somebody, not that something once was.
  setRiderKyc: (email: string, kyc: Record<string, unknown>) =>
    rpc<void>('admin_set_rider_kyc', { p_email: email, p_kyc: kyc }),

  /// The database refuses to verify an incomplete or already-expired file, and
  /// refuses to reject without a reason. Both messages are written for the admin
  /// reading them and are passed straight through.
  reviewRiderKyc: (email: string, verified: boolean, reason?: string) =>
    rpc<void>('admin_review_rider_kyc', {
      p_email: email,
      p_verified: verified,
      p_reason: reason ?? null,
    }),

  /// Lets a rider work without the documents on file, or takes that away again.
  ///
  /// Not a way of verifying somebody: it is stored separately, it leaves the
  /// document status exactly where it was, and switching it off puts the rider
  /// straight back to whatever their papers say (0083). The database insists on
  /// a reason and refuses an expiry date that has already passed.
  ///
  /// `until` is an ISO date or null for no expiry. Null is a real choice, not a
  /// default — an override that never ends is how the KYC gate quietly stops
  /// existing.
  overrideRiderKyc: (
    email: string,
    on: boolean,
    reason?: string,
    until?: string | null,
  ) =>
    rpc<void>('admin_override_rider_kyc', {
      p_email: email,
      p_on: on,
      p_reason: reason ?? null,
      p_until: until ?? null,
    }),

  setRiderPayRates: (baseFee: number, perKmFee: number) =>
    rpc<void>('admin_set_rider_pay_rates', {
      p_base_fee: baseFee,
      p_per_km_fee: perKmFee,
    }),

  /// Every rider and what they are holding, including the ones holding nothing
  /// (migration 0076). "Everybody is settled" is a thing ops needs to be able to
  /// see, and a screen that empties when all is well looks broken.
  listRiderCash: () => rpc<RiderCashRow[]>('admin_rider_cash'),

  riderCashLedger: (email: string) =>
    rpc<RiderCashEntry[]>('admin_rider_cash_ledger', {
      p_email: email,
      p_limit: 100,
    }),

  /// Positive rupees, the way somebody counting notes says it. The database
  /// stores it negative and refuses a deposit larger than the balance.
  recordCashDeposit: (email: string, amount: number, reference: string) =>
    rpc<void>('admin_record_cash_deposit', {
      p_email: email,
      p_amount: amount,
      p_reference: reference,
    }),

  /// Signed, and the only way a balance moves without money moving — a write-off
  /// for a rider who disappeared, or a correction to a mistyped deposit. The
  /// note is mandatory on the database side.
  adjustRiderCash: (email: string, amount: number, note: string) =>
    rpc<void>('admin_adjust_rider_cash', {
      p_email: email,
      p_amount: amount,
      p_note: note,
    }),

  setRiderCashCap: (cap: number) =>
    rpc<void>('admin_set_rider_cash_cap', { p_cap: cap }),

  /// Every refund, or one status of them (migration 0077). Oldest first, because
  /// this is a work queue and the thing that has waited longest is the thing
  /// somebody is chasing.
  listRefunds: (status?: RefundRow['status']) =>
    rpc<RefundRow[]>('admin_list_refunds', { p_status: status ?? null }),

  /// A refund raised by hand: the partial the customer is owed for a missing
  /// dish, and the only way to refund a cash order that was actually delivered.
  /// Born `requested` — issuing and approving are two acts and both get a name.
  issueRefund: (
    orderId: string,
    amount: number,
    reason: string,
    fundedBy: RefundRow['funded_by'],
  ) =>
    rpc<number>('admin_issue_refund', {
      p_order_id: orderId,
      p_amount: amount,
      p_reason: reason,
      p_funded_by: fundedBy,
    }),

  /// Clears it to be sent, and is the one chance to move who pays for it — the
  /// database refuses the change once a settlement has absorbed the row.
  approveRefund: (id: number, fundedBy?: RefundRow['funded_by']) =>
    rpc<void>('admin_approve_refund', {
      p_id: id,
      p_funded_by: fundedBy ?? null,
    }),

  declineRefund: (id: number, reason: string) =>
    rpc<void>('admin_decline_refund', { p_id: id, p_reason: reason }),

  /// Records that the money went back — it does not send it. There is no gateway
  /// yet (PAY-001), so this is a transfer somebody made and came back to log,
  /// exactly like a settlement or a rider payout. The reference is mandatory for
  /// the same reason theirs are.
  markRefundPaid: (id: number, reference: string) =>
    rpc<void>('admin_mark_refund_paid', { p_id: id, p_reference: reference }),

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

  /// The complaint queue (0095), oldest first — this is a worklist, and the
  /// complaint that has waited longest is the one that has waited longest.
  /// `status` null means every ticket, open and closed.
  supportTickets: (f: {
    status?: 'open' | 'resolved' | null
    limit?: number
    offset?: number
  }) =>
    rpc<SupportTicketRow[]>('admin_support_tickets', {
      p_status: f.status ?? null,
      p_limit: f.limit ?? 50,
      p_offset: f.offset ?? 0,
    }),

  /// Closes a ticket, with a note that goes back to the customer. One-way:
  /// there is no reopen, so a complaint that comes back is a new one and the
  /// queue stays honest about how many times somebody had to ask.
  ///
  /// This settles nothing on its own. If money is owed, `issueRefund` is still
  /// the call that owes it — a complaint that refunded itself would be a
  /// complaint worth making up.
  resolveTicket: (id: number, note: string) =>
    rpc<string>('admin_resolve_ticket', { p_id: id, p_note: note }),

  /// The three photographs of an order (0094): cooked and packed by the
  /// kitchen, the handover by the rider.
  ///
  /// One order at a time, because that is how a complaint arrives — a list of
  /// fifty rows has no use for three URLs each. Always returns a row for an
  /// order that exists, even when all three are null: "this one has no
  /// photographs" is an answer, and an empty result would read as a lookup
  /// failure.
  /// The gift fulfilment queue (0096), oldest first. `status` null means every
  /// one. Zopiqnow packs and couriers these, so this queue is the only thing
  /// that moves a gift order along — there is no vendor app behind it.
  giftOrders: (f: {
    status?: GiftOrderStatus | null
    limit?: number
    offset?: number
  }) =>
    rpc<GiftOrderRow[]>('admin_gift_orders', {
      p_status: f.status ?? null,
      p_limit: f.limit ?? 50,
      p_offset: f.offset ?? 0,
    }),

  giftOrderItems: (orderId: string) =>
    rpc<GiftOrderLineRow[]>('admin_gift_order_items', { p_order_id: orderId }),

  /// Moves one along. The ladder only goes forward — placed → accepted →
  /// dispatched → delivered, with a cancel available until it is with a courier.
  ///
  /// `dispatched` is refused without a courier name: a parcel marked on its way
  /// with nobody named is a customer who cannot ask anybody anything.
  setGiftOrderStatus: (
    orderId: string,
    status: GiftOrderStatus,
    opts?: { courier?: string; tracking?: string; reason?: string },
  ) =>
    rpc<string>('admin_set_gift_order_status', {
      p_order_id: orderId,
      p_status: status,
      p_courier_name: opts?.courier ?? null,
      p_tracking_ref: opts?.tracking ?? null,
      p_reason: opts?.reason ?? null,
    }),

  orderPhotos: (orderId: string) =>
    rpc<OrderPhotoRow[]>('admin_order_photos', { p_order_id: orderId }),

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
    /// The caps (0075). Null is "no limit" for all three numeric ones — and for
    /// max_per_user that has to be said explicitly, because the column defaults
    /// to 1 and a campaign meant to be reusable would otherwise quietly become
    /// once-per-customer.
    max_redemptions: number | null
    max_per_user: number | null
    budget: number | null
    first_order_only: boolean
    is_public: boolean
  }) =>
    rpc<string>('admin_save_coupon', {
      p_code: c.code,
      p_min_subtotal: c.min_subtotal,
      p_flat_off: c.flat_off,
      p_percent_off: c.percent_off,
      p_max_off: c.max_off,
      p_valid_until: c.valid_until,
      p_max_redemptions: c.max_redemptions,
      p_max_per_user: c.max_per_user,
      p_budget: c.budget,
      p_first_order_only: c.first_order_only,
      p_is_public: c.is_public,
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

  /// Moves a pending statement by a signed amount and records why (0079).
  /// Refused once the statement is paid — the money has gone, and the honest
  /// place for a correction is the next week.
  adjustSettlement: (id: number, amount: number, reason: string) =>
    rpc<number>('admin_adjust_settlement', {
      p_id: id,
      p_amount: amount,
      p_reason: reason,
    }),

  listSettlementAdjustments: (id: number) =>
    rpc<SettlementAdjustmentRow[]>('admin_list_settlement_adjustments', {
      p_id: id,
    }),

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

/// What a customer said went wrong (0095).
///
/// The category is the database's value, not a label — `ISSUE_LABEL` below
/// turns it into English. Keeping the two apart means the wording can change
/// without a migration and without breaking a filter.
export type SupportTicketRow = {
  id: number
  order_id: string
  category: IssueCategory
  body: string | null
  status: 'open' | 'resolved'
  created_at: string
  resolved_at: string | null
  resolved_by: string | null
  /// What was written back. The customer reads this on their own receipt.
  admin_note: string | null
  restaurant_name: string
  order_status: OrderStatus
  order_total: number
  customer_phone: string
  /// The size of the full match, repeated on every row — the pager reads it.
  total_count: number
}

export type IssueCategory =
  | 'missing_item'
  | 'wrong_item'
  | 'quality'
  | 'damaged'
  | 'late'
  | 'never_arrived'
  | 'rider'
  | 'payment'
  | 'other'

/// Deliberately terser than the customer's own wording. They wrote "Something
/// was missing"; support is triaging fifty of these and wants the noun.
export const ISSUE_LABEL: Record<IssueCategory, string> = {
  missing_item: 'Missing item',
  wrong_item: 'Wrong item',
  quality: 'Food quality',
  damaged: 'Spilled or damaged',
  late: 'Very late',
  never_arrived: 'Never arrived',
  rider: 'Delivery partner',
  payment: 'Payment',
  other: 'Other',
}

/// The evidence an order carries (0094). Every field is nullable and that is
/// the point: an order placed before the feature has none, and the gate that
/// asks for them lives in the two apps rather than in the database, so a missing
/// one means "nobody took it", not "the request failed".
export type OrderPhotoRow = {
  order_id: string
  status: OrderStatus
  /// Off the pass, by the kitchen.
  cooked_photo_url: string | null
  /// The sealed bag, by the kitchen.
  packed_photo_url: string | null
  /// The doorstep, by the rider. Written only when the delivery code was right.
  delivery_photo_url: string | null
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
  valid_from: string | null
  valid_until: string | null
  is_active: boolean
  created_at: string
  /// The caps (0075). Null means unlimited in all three cases.
  max_redemptions: number | null
  max_per_user: number | null
  budget: number | null
  first_order_only: boolean
  is_public: boolean
  /// Whose money the discount is (0074). Restaurant-funded codes come off that
  /// restaurant's settlement; platform ones come off promotional spend.
  funded_by: 'platform' | 'restaurant'
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
/// Money owed back on one order (migration 0077).
///
/// `requested_by` is the whole difference between the two kinds. `'system'` is
/// the automatic full refund a cancellation, a rejection or the five-minute
/// expiry raised — already approved, and not declinable. Anything else is an
/// admin's email, and that one waits for approval.
export type RefundRow = {
  id: number
  order_id: string
  restaurant_id: string
  restaurant_name: string
  user_phone: string
  order_total: number
  payment_method: 'cod' | 'upi'
  amount: number
  status: 'requested' | 'approved' | 'processing' | 'paid' | 'failed' | 'declined'
  reason: string
  funded_by: 'platform' | 'restaurant'
  requested_by: string
  approved_by: string | null
  gateway_refund_id: string | null
  failure_reason: string | null
  /// The date the customer was promised, frozen when the refund was raised.
  expected_by: string
  settlement_id: number | null
  created_at: string
  paid_at: string | null
}

export type SettlementRow = {
  id: number
  restaurant_id: string
  restaurant_name: string
  period_start: string
  period_end: string
  /// The date this statement may be paid on or after — `period_end` plus the
  /// platform hold (0079). The window a refund or an adjustment has to land in.
  hold_until: string
  order_count: number
  gross_sales: number
  /// What the restaurant's own offers cost it this week. Comes off gross before
  /// commission (0074) — a non-zero figure here is a restaurant-funded promotion,
  /// which is the thing that used to be indistinguishable from a platform one.
  vendor_funded_discount: number
  commission: number
  /// Restaurant-funded refunds charged to this statement (0077). Not week-scoped
  /// like the rest of the row — a refund raised this week for a month-old order
  /// lands here, because the week it belongs to has already been paid.
  refunds: number
  /// The signed sum of this statement's adjustments (0079). Positive credits the
  /// restaurant, negative charges it. Added last, after commission and refunds.
  adjustments: number
  net_payable: number
  status: 'pending' | 'paid'
  reference: string | null
  has_bank: boolean
  /// Still inside its hold — pending, and `hold_until` has not arrived.
  /// `admin_mark_settlement_paid` refuses while this is true, so the button and
  /// the function are reading the same fact rather than two versions of it.
  on_hold: boolean
  paid_at: string | null
}

/// One line of a statement's adjustment history, with the admin who wrote it.
/// The rollup on [SettlementRow.adjustments] is for the arithmetic; these are
/// what somebody reads three months later to find out why.
export type SettlementAdjustmentRow = {
  id: number
  amount: number
  reason: string
  created_by: string
  created_at: string
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
  /// The silent looping MP4 played over the still (0072 — an animated WebP until
  /// then). Null is the ordinary case — most slides are a photograph — and the
  /// still is what shows when it is absent, still buffering, or the phone has
  /// asked for reduced motion.
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
  /// What the week earned, what was kept back against COD cash the rider was
  /// still holding, and what is actually transferred (migration 0076).
  /// `amount = gross_amount - cash_withheld`, and the database has a constraint
  /// saying so.
  gross_amount: number
  cash_withheld: number
  amount: number
  status: 'pending' | 'paid'
  reference: string | null
  has_bank: boolean
  paid_at: string | null
}

/// One rider's cash position (migration 0076). `outstanding` is the sum of the
/// ledger and is the only number that decides anything; the totals beside it are
/// there so a figure that looks wrong can be argued with.
export type RiderCashRow = {
  partner_email: string
  partner_name: string
  phone: string
  is_active: boolean
  outstanding: number
  collected_total: number
  /// Reported positive, though the ledger stores deposits negative so the
  /// balance can be a plain sum.
  deposited_total: number
  adjusted_total: number
  collections: number
  last_collected_at: string | null
  last_deposit_at: string | null
  /// The platform-wide ceiling, repeated on every row so the list is one call.
  cap: number
}

/// A line of the ledger behind [RiderCashRow.outstanding]. Signed: a collection
/// is positive, a deposit and a payout netting are negative.
export type RiderCashEntry = {
  id: number
  kind: 'collected' | 'deposited' | 'adjustment'
  amount: number
  order_id: string | null
  payout_id: number | null
  reference: string | null
  note: string | null
  recorded_by: string | null
  created_at: string
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

/// What somebody is on the platform. Reported most-privileged-first by
/// `admin_list_users`, so a person who is both staff and an admin reads as an
/// admin — which is the answer that matters when deciding whether to block them.
export type UserRole = 'admin' | 'vendor' | 'rider' | 'customer'

/// A person, with the counts the list is read by.
///
/// The three order counts are three different stories and are deliberately not
/// summed into one: `delivered` is a completed sale, `rejected` is a restaurant
/// refusing, `cancelled` is the order being called off. Ten orders with nine
/// cancellations is a different person from ten with nine deliveries.
export type UserRow = {
  user_id: string
  email: string | null
  phone: string | null
  name: string | null
  role: UserRole
  created_at: string
  last_sign_in_at: string | null
  is_blocked: boolean
  blocked_until: string | null
  total_orders: number
  delivered_orders: number
  rejected_orders: number
  cancelled_orders: number
  /// Paise-free rupees, summed over delivered orders only — money that actually
  /// changed hands, not money that was once in a cart.
  total_spend: number
}

export type UserAddress = {
  id: string
  label: string | null
  line1: string | null
  city: string | null
  delivery_notes: string | null
  created_at: string
}

/// One row of the moderation ledger. Append-only: an unblock does not erase the
/// block, it follows it, which is the point of keeping a record at all.
export type UserModeration = {
  id: number
  action: 'block' | 'unblock'
  reason: string | null
  actor_email: string
  created_at: string
}

export type UserDetail = UserRow & {
  addresses: UserAddress[]
  restaurants: { restaurant_id: string; role: string; name: string | null }[]
  moderation: UserModeration[]
}

export type UserOrder = {
  id: string
  restaurant_name: string | null
  status: string
  total: number
  payment_method: string | null
  delivery_to: string | null
  created_at: string
  items: { name: string; quantity: number; unit_price: number }[]
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
  kyc_status: KycStatus
  /// Not the same question as `kyc_status !== 'verified'`. A rider verified in
  /// March whose insurance lapsed last night is still 'verified' and is still
  /// blocked — the expiry is recomputed on every read (0080).
  kyc_blocked: boolean
  /// A third question again, and not a fourth way of saying the other two: this
  /// rider is working because an admin vouched for them, not because anybody
  /// read their documents (0083). Never render it as "verified".
  kyc_overridden: boolean
}

export type KycStatus = 'pending' | 'verified' | 'rejected'

/// What Zopiqnow holds on file about a rider. Never leaves the console: the
/// table has no RLS policy for anybody and the scans are in a private bucket, so
/// the rider's own app can see their *status* and nothing else (0080).
export type RiderKyc = {
  partner_email: string
  vehicle: Vehicle
  licence_number: string | null
  licence_expiry: string | null
  licence_doc_path: string | null
  insurance_policy: string | null
  insurance_expiry: string | null
  insurance_doc_path: string | null
  id_proof_kind: 'aadhaar' | 'pan' | null
  id_proof_number: string | null
  id_proof_doc_path: string | null
  vehicle_number: string | null
  rc_doc_path: string | null
  status: KycStatus
  rejected_reason: string | null
  reviewed_at: string | null
  reviewed_by: string | null
  blocked_reason: string | null
  /// The override (0083). Separate from `status` on purpose — `status` keeps
  /// meaning "somebody read the documents", and these say "somebody decided to
  /// do without them". A rider can be `pending` here and still working.
  override_reason: string | null
  override_by: string | null
  override_at: string | null
  /// Last day it applies. Null means it does not run out on its own.
  override_until: string | null
  /// Whether it is in force *today* — a reason plus an unexpired date. Read this
  /// rather than testing `override_reason` yourself.
  override_active: boolean
}

/// One gift order in the fulfilment queue (migration 0096).
///
/// Zopiqnow packs and couriers these — there is no vendor app and no rider in
/// this story, so this queue is the *only* thing that moves one along.
export type GiftOrderRow = {
  id: string
  shop_id: string
  shop_name: string
  status: GiftOrderStatus
  status_reason: string | null
  subtotal: number
  delivery_fee: number
  taxes: number
  total: number
  payment_id: string | null
  customer_phone: string
  delivery_to: string
  delivery_notes: string | null
  courier_name: string | null
  tracking_ref: string | null
  created_at: string
  dispatched_at: string | null
  delivered_at: string | null
  item_count: number
  total_count: number
}

export type GiftOrderStatus =
  | 'placed'
  | 'accepted'
  | 'dispatched'
  | 'delivered'
  | 'cancelled'

export const GIFT_STATUS_LABEL: Record<GiftOrderStatus, string> = {
  placed: 'New',
  accepted: 'Preparing',
  dispatched: 'With courier',
  delivered: 'Delivered',
  cancelled: 'Cancelled',
}

export type GiftOrderLineRow = {
  name: string
  unit_price: number
  quantity: number
  line_total: number
  tax_amount: number
}
