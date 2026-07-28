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
| Backend — ETA calculation | ✅ Dynamic since B3 — recomputed from the rider's live position and this order's own road/straight-line detour factor (`orders.eta_at`, 0057). Moves later only with a reason printed on the card |
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

### B0 — Unblock push ✅ **DONE 2026-07-25** (by the user)
- [x] Firebase project(s) + `google-services.json` for customer and rider apps
- [x] `supabase secrets set FCM_SERVICE_ACCOUNT`
- [x] `supabase functions deploy send-notification --no-verify-jwt`
- [x] Notifications-INSERT database webhook — trigger `push_on_notification_insert`
- [x] Verify a real push on a release build on a device

Everything in `PUSH_NOTIFICATIONS.md`. **B3's dispatch is now unblocked** — an offer
push with Accept/Decline is buildable, and the 20s board poll can go.

Still owed, small:
- [ ] `supabase functions delete send-order-push` — the superseded function is still
      ACTIVE beside `send-notification`, and a dead endpoint nobody calls is one
      somebody wires back up
- [ ] Commit the rider in-app notification inbox (built, analyze-clean, uncommitted —
      entangled with the current rider UI WIP, which also carries a stray
      `apps/rider/lib/lib/app/rider_shell.dart` that does not compile)

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

**B2a — cancellation and the timeout ✅ DONE 2026-07-25** (migration 0051)

- [x] Customer cancellation flow — allowed until `preparing`, refused after, with the
      reason shown in plain words (never a silent disabled button). `cancel_my_order`
      refuses with a *sentence about this order* — "the kitchen has already started",
      "packed and waiting for a rider", "already on its way" — and the screen shows it
      verbatim, whether it arrives before the tap or after it
- [x] Vendor **auto-timeout**: 5 minutes, `expire_unaccepted_orders()` on pg_cron every
      minute, `skip locked` so an accept in flight always wins the race. The deadline
      lives on `orders.accept_deadline`, which is also what the vendor ticket counts
      down to — one column, so the tablet and the sweeper can never disagree
- [x] A cancelled order releases its rider — `release_order_delivery` cancels the
      delivery, deletes both codes, and tells the rider why their job vanished

**B2b — refunds, deferred to after B4.** A `refunds` state machine built now would be a
ledger with nothing behind it: checkout still runs on `MockPaymentGateway` and no money
has ever moved. Building it against a real gateway once beats building it twice.

- [ ] `refunds` table + state machine (requested → approved → paid), FK to the order
- [ ] Refund on cancel-after-payment and on vendor rejection
- [ ] Customer: order issue / report screen, feeding a support queue
- [ ] Admin: refund management console

**A hole found and closed on the way:** 0050 did not do what it says. 0015 had widened
`set_order_status` to four arguments (`p_prep_minutes`); 0050 wrote a *three*-argument
function to close the vendor's back door into the rider's half of the story — and
Postgres overloads rather than replaces across a different argument list. Both existed,
and the vendor app, which passes `p_prep_minutes` on every call, bound to the
four-argument one: the 0015 body, with `ready_for_pickup → out_for_delivery` and
`out_for_delivery → delivered` still on its ladder. The wall was built beside the door.
Nothing exploited it — the app stopped offering the buttons in the same commit — but "the
app does not ask" is exactly the guarantee 0050 was written to stop relying on. 0051
collapses the two into one function and drops the overload.

**Rule:** a cancelled order must release its rider (`abandon_delivery`) and never leave a
`deliveries` row pointing at a dead order.

**Lesson for every migration from here:** `create or replace function` with a changed
argument list is a **new function**, not a replacement. Any migration that redefines an
existing function must `drop function` the old signature explicitly, and the edge-case
run must assert the overload count.

---

### B3 — Dispatch, live tracking, dynamic ETA ✅ *(2026-07-28, migrations 0056–0057)*
- [x] **Rider assignment algorithm** — `dispatch_deliveries()` runs every 20s and offers
      the job to *one* rider: fewest live jobs first, then nearest, then longest idle.
      A sheet with a 45-second countdown, Accept / Decline
- [x] **Auto-reassignment** — decline re-offers **inline** (not at the next sweep);
      a timeout is retired by the sweeper; an abandon leaves the order with no live
      delivery, which the sweeper picks up on its next tick. A rider hears about an
      order at most once — `(order_id, partner_email)` is unique, so a decline is final
- [x] **Rider location stream** — `rider_locations`, one row per rider (a fix, not a
      track), written by `record_rider_location` on a 30 m / 20 s stream while carrying
- [x] **Live map** — custom-painted, on the tracking card. Ola's `overview_polyline` is
      stored by 0057 and decoded on the device, so the *real road* is drawn with no
      tile server, no key in the APK, and no new dependency
- [x] **Dynamic ETA** — `recompute_order_eta` runs off every position fix and every
      status change; `orders.eta_at` replaces `created_at + eta_minutes`, and the live
      card (0052) reads the new number over the channel it already had
- [x] Rider board: distance **and** pay before claiming, on both the board card and the
      offer sheet (`available_deliveries` now returns `route_km` and `rider_pay`)
- [x] Deleted the 20s board polling — and its test, whose whole subject was the timer.
      `delivery_offers` has a rider-scoped policy, so Realtime can carry the signal that
      `available_deliveries` (a function) never could

**Rules, and where each one is actually enforced:**
- *Location is retained only while the job is live.* Two places, not one:
  `record_rider_location` **deletes** the row when the caller has nothing live, and
  `purge_rider_locations` (folded into the dispatcher's tick) sweeps anything a dead
  phone left behind.
- *A customer may never read a rider's position outside their own live order.* One RLS
  policy on `rider_locations`, the same shape as 0039's. The `partner_email` the app
  subscribes with is a **filter, not a credential** — the policy returns nothing for
  somebody else's rider.
- *The ETA must never move backwards without a reason on screen.* Enforced in one place,
  at the bottom of `recompute_order_eta`: earlier is free; later is written **only**
  together with `eta_reason`, and where no cause can be named the old time stands. The
  card renders that sentence under the arrival time. Movement under two minutes either
  way is not written at all, so the number does not twitch at a traffic light.

**The board did not die, and that is deliberate.** "Auto-assign instead of self-claim"
read literally means deleting `available_deliveries` — which strands every order the
fleet declines, and on a thin night that is every order. So an order that exhausts its
offers goes back on the open board, and *that* is when the broadcast push fires: at the
moment it is actually true that anybody may take it. The board is the leftovers now, not
the front door, and the empty-state copy was rewritten to stop telling riders to watch it.

**Two decisions worth keeping.** Riders are *ranked*, not filtered, by live job count —
8b-4 left concurrent claims uncapped on purpose ("carrying three orders from one street
is how delivery actually works"), and excluding busy riders would have quietly reversed
that; a rider already at the kitchen is the nearest busy one, so batching falls out for
free. And `accept_offer` goes through `claim_delivery` untouched: the partial-unique-index
race is still the thing that decides a tie, exactly as it did from the board.

**A bug this phase created and closed before shipping.** The first cut of the pre-pickup
estimate fell back to `created_at + eta_minutes` for the kitchen's ready time when a
vendor accepted without a prep time — then added the ride on top. That is the *delivery*
promise, not the kitchen's, so a 32-minute promise on a 12 km route came out as 68
minutes. It now subtracts the ride back out of the promise, which makes the whole
expression collapse to the original number: no new information, no new estimate.

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
