# Zopiqnow — Zomato parity checklist

**Created:** 2026-07-24 · **Goal:** industry-grade, end-to-end, no gap in the workflow
and no way to skip a step. This file supersedes the ad-hoc feature lists; it is the
one place that says what is genuinely missing.

Legend: `[x]` done · `[~]` partial (what's missing is named) · `[ ]` not built.

---

## Part A — already at parity (audited 2026-07-24, removed from the "missing" list)

These were on the gap list but are shipped and verified. Kept here so nobody rebuilds them.

| Claimed missing | Reality |
|---|---|
| Customer — live order status timeline | ✅ `/orders/:id` is a live timeline over Supabase Realtime (Step 8, migration 0008) |
| Customer — rider details (name, vehicle) | ✅ `OrderRider{name, phone, vehicle}` on the tracking card, RLS-scoped to `state='picked_up'` (0039). **No photo** — the roster stores none |
| Vendor — order state flow Accept → Preparing → Ready | ✅ Full six-status machine incl. `ready_for_pickup` + `rejected` (0014) |
| Vendor — pickup OTP verification | ✅ 4-digit code, vendor reads → rider types → `confirm_pickup` (0025). **QR not built** (OTP is sufficient; QR is cosmetic) |
| Vendor — prep time on accept | ✅ Prep-time sheet + `ready_by` + `Ready in Xm` / `Over by Xm` countdown (0015). **Cannot be revised after accepting** |
| Vendor — restaurant preparation timer | ✅ same as above |
| Rider — navigation to restaurant / to customer | ✅ `geo:` hand-off to the rider's own maps app, target switches with job state (8g). Not *in-app* navigation |
| Rider — "Picked Up" | ✅ `confirm_pickup` |
| Rider — earnings screen | ✅ Earnings tab: totals, per-job arithmetic, payouts (8c/8d) |
| Rider — delivery history | ✅ Per-job list inside Earnings (`my_deliveries`) |
| Backend — role-based permissions | ✅ Owner/staff (0024), rider identity, admin `assert_admin()`, RLS on every table |
| Backend — proper order state machine | ✅ Transition table lives in Postgres (0014); apps mirror it, DB wins |
| Backend — real-time status sync | ✅ Realtime on `orders` + `notifications`, RLS applied per subscriber |
| Backend — ETA calculation | ~ Quoted at placement + prep-time + real road distance (`orders.route_km`, Ola Maps, 0046). **Not dynamic** — see B3 |
| Important — coupon flow (customer side) | ✅ Apply/remove, server-validated, discount frozen onto the order |
| Admin — rider management | ✅ Roster, add/edit, activate/deactivate with a live-job guard (0040) |
| Admin — vendor approval | ✅ Full onboarding console; `admin_publish_restaurant` (0026–0038) |
| Security — only rider can mark delivered | ✅ `confirm_delivered` keyed on `delivery_partner_email()` |
| Security — only vendor can mark ready | ✅ `set_order_status` keyed on `staff_restaurant_id()`; vendors have **no** `update` grant on `orders` |
| Security — state validation (no skipping) | ✅ Enforced in the DB, not the client |
| Security — duplicate pickup/delivery protection | ✅ Partial unique index on `deliveries(order_id) where state<>'cancelled'`; `confirm_pickup`/`confirm_delivered` scoped to the live row + order status (8b-4) |
| Push notifications | ~ **All code written**, both send + device side. Undeployed — see B0 |

---

## Part B — the real remaining work

### B0 — Unblock push (owed by the user, not buildable here)
- [ ] Firebase project(s) + `google-services.json` for customer and rider apps
- [ ] `supabase secrets set FCM_SERVICE_ACCOUNT`
- [ ] `supabase functions deploy send-notification --no-verify-jwt` (**not** the old `send-order-push`)
- [ ] Notifications-INSERT database webhook
- [ ] Verify a real push on a release build on a device

Everything in `PUSH_NOTIFICATIONS.md`. **B3's dispatch and B1's alerts are half-blind
until this is live** — the rider board still polls every 20s because of it.

Also owed: commit the rider in-app notification inbox (built, analyze-clean, uncommitted
— entangled with the current rider UI WIP).

---

### B1 — Close the delivery lifecycle ✅ **DONE 2026-07-24** (migration 0049)
The single biggest hole: between "claimed" and "delivered" the system was blind, and a
delivery could be marked complete by a rider who never met the customer.

- [x] `deliveries.state` gains `arrived_at_restaurant` and `arrived_at_customer`
- [x] Rider: **"I've arrived at restaurant"** → vendor ticket shows *At the counter · waiting Xm*
- [x] Rider: **"I've arrived at customer"** → customer card shows *Waiting outside*
- [x] **Delivery OTP** — 4 digits on the customer's tracking card, typed into
      `confirm_delivered`. This is what makes "delivered" mean something
- [x] Vendor: rider-arrival status on the ticket
- [x] Rider: **online / offline self-toggle**, refused while carrying
- [x] Customer: delivery code + "rider is here" state

**A hole found and closed on the way:** the *pickup* code had been readable by the rider
it was meant to test — 0025 stored it on `deliveries.pickup_otp` and gave riders `select`
on their own row, so a rider could confirm a pickup from the road. Both codes now live in
`delivery_codes`, a table with **no policies at all**, read through one function per
identity. Five wrong guesses locks a code; whoever reads it aloud reissues it.

**Rules now enforced in Postgres:** no state may be skipped (`confirm_pickup` refuses from
`claimed`, `confirm_delivered` from `picked_up`); a wrong code is *returned*, not raised,
so the attempt counter survives; going offline while carrying is refused.

---

### B2 — Cancellation, refunds, and the accept timeout
Today only a vendor can end an order early, and no money ever comes back.

- [ ] Customer cancellation flow — allowed until `preparing`, refused after, with the
      reason shown in plain words (never a silent disabled button)
- [ ] Vendor **auto-timeout**: an order not accepted within N minutes auto-rejects and
      tells the customer. Runs in Postgres (pg_cron), not in an app that might be closed
- [ ] `refunds` table + state machine (requested → approved → paid), FK to the order
- [ ] Refund on cancel-after-payment and on vendor rejection
- [ ] Customer: order issue / report screen, feeding a support queue
- [ ] Admin: refund management console

**Rule:** a cancelled order must release its rider (`abandon_delivery`) and never leave a
`deliveries` row pointing at a dead order.

---

### B3 — Dispatch, live tracking, dynamic ETA
- [ ] **Rider assignment algorithm** — auto-offer the nearest free rider instead of
      self-claim. Needs push (B0) to be an *offer* with Accept/Decline and a countdown
- [ ] **Auto-reassignment** on decline, timeout, or abandon
- [ ] **Rider location stream** — `rider_locations`, written on an interval while carrying,
      readable only by that order's customer while `state='picked_up'`
- [ ] **Live map** on the customer tracking screen (Ola Maps; the credential and the
      Origin-header pattern already work from 0046)
- [ ] **Dynamic ETA** — recomputed from rider position + road distance, pushed over
      Realtime, replacing the static quote
- [ ] Rider board: show distance and pay **before** claiming (`route_km` is already stored)
- [ ] Delete the 20s board polling in the same commit that lands the offer push

**Rules:** location is retained only while the job is live; a customer may never read a
rider's position outside their own live order; the ETA must never move backwards without
a reason on screen.

---

### B4 — Payments, for real
- [ ] Razorpay checkout (dep approved + pinned since 2026-07-10)
- [ ] Server-created payment order — the client must never name an amount
- [ ] **Signature verification** server-side before an order is placed
- [ ] Payment status on the order; a failed payment must not create a half-order
- [ ] Refund path wired to B2

---

### B5 — Communication
- [ ] Customer → rider call (`url_launcher` is already in the lockfile; masked number later)
- [ ] Customer → restaurant call
- [ ] Rider → restaurant call
- [ ] Customer ↔ rider chat (canned messages first — a live chat needs moderation and history)
- [ ] **Delivery instructions** on the address / at checkout, surfaced to the rider

---

### B6 — Ratings, reviews, invoice, offers
- [ ] `reviews` table — one per delivered order, customer-written, immutable after a window
- [ ] Customer: rate order + restaurant + rider after delivery
- [ ] Vendor: Reviews room (currently a "coming soon" tile that lies)
- [ ] Rating recomputation as a trigger, never a client write
- [ ] **Digital invoice** — GST-shaped, downloadable, from the frozen order lines
- [ ] Vendor-created offers (needs `restaurant_id` on coupons + `place_order` line pricing
      + the customer strikethrough)

---

### B7 — Admin panel completion
- [ ] Live order monitoring (every open order, its status, its rider)
- [ ] Coupon management
- [ ] Push notification panel
- [ ] Platform analytics dashboard (vendor-scoped analytics exists; platform-wide does not)
- [ ] Vendor settlement reports (rider payouts page exists; the vendor side is vendor-only)
- [ ] Admin force-abandon / support override — the known structural gap from 8b-4

---

### B8 — Hardening (runs last, but the rules apply from B1 onward)
- [ ] Rider identity verification / KYC — documents on the roster, admin-verified
- [ ] Fraud: velocity limits, a cap on concurrent claims, OTP attempt caps
- [ ] `/security-review` over every new RPC and policy
- [ ] **`revoke all on function X from public, anon, authenticated`** on every ops-only
      function — the 0045 lesson; revoking from PUBLIC alone is not enough on Supabase
- [ ] Edge-case matrix per phase, run against the live DB in a rolled-back transaction
- [ ] Perf: rebuild/scroll profiling on the Android 10 floor, pagination, image caching
- [ ] **Release-APK manifest check for every app** — the rider's missing `INTERNET`
      permission shipped dead for four phases. "It builds" is not "it runs"

---

## Standing rules for every slice below

1. **The database is the trust boundary.** A rule that only the app enforces is not enforced.
2. **No new `orders.status` value without a tolerant customer build already shipped**
   (`OrderStatus.fromWire` throws on unknown).
3. **One vertical slice at a time**, verified against the live DB in a rolled-back
   transaction *and* on the Android 10 device before it counts as done.
4. **Version freeze holds** — a new dependency is an explicit approved request, and the
   lockfile is diffed after every pin.
5. **No optimistic UI on money or on state a customer can see** — flip only what can be
   safely reverted with a sentence.
