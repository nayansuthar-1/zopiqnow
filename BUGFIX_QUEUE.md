# Bug queue — sweep of 2026-08-12

Findings from a cross-app sweep of `apps/customer`, `apps/vendor`, `apps/rider`,
`apps/admin-web`, all 119 migrations and the 6 edge functions. **Nothing below is
a static error** — the analyzer reports no errors anywhere, only 16 warnings and
infos in the customer app (unused locals, three dead widgets in
`order_detail_page.dart`, deprecated `withOpacity`), none of them related to any
item here. Every finding is semantic, and several were only visible by reading the
live database rather than the migrations.

Worked **one at a time, top down.** Tick an item off by moving it to *Closed* with
the migration or commit that closed it, the way `REMAINING.md` does — a stale
tracker costs more than an untracked task.

---

## The live state that frames all of this

Re-check these before acting on any item; they are the reason several findings are
"launch blocker" rather than "we are being robbed today".

| Fact | Value on 2026-08-12 | Why it matters |
|---|---|---|
| `payment_settings.require_verified_payment` | **false** | The gate is disarmed. `place_order` takes any non-empty `payment_id`. |
| `payment_intents` | **0 rows** | Razorpay was never configured. All 55 orders went through `MockPaymentGateway`. |
| `pg_stat_database.deadlocks` | **0** | The concurrency findings are latent, not firing. |
| `dispatch-deliveries` avg runtime | **0.01 s** over 12,944 runs | Nothing overlaps yet. It will at volume. |
| `refunds` | **20 rows, ₹7,155, all `approved`** | Oldest `expected_by` was 2026-08-07. Nothing pays them. |
| `orders` | 55, from 7 customers | Pre-launch. No real customer money has moved. |

So: **no real money has been lost.** Every money item below is a thing that fires
on the day Razorpay goes live, which is exactly why they sit above the rest.

---

## Open

### P1a — `place_order` cannot be called twice in one transaction

Found while building P1's verification. `place_order` opens with

    create temp table _lines (…) on commit drop

and `on commit drop` drops at **commit**, not at statement end. So a second call
inside the same transaction dies with `relation "_lines" already exists`.

Not reachable today: PostgREST gives every RPC its own transaction, so no customer
can hit it. It is a landmine for the first thing that ever calls `place_order`
twice in one transaction — a batch re-order, an admin "place this again" helper, a
test harness, or a future function that loops. `create temp table if not exists`
plus a `delete from _lines` would make it safe; so would `on commit drop` becoming
an explicit `drop` at the end.

Filed rather than fixed with P1 because it is a different bug in a different
function, and the rule is one at a time.

---

### P3 — Refunds are promised with a date and nothing pays them

`orders_refund_on_termination` inserts the refund already `approved` and pushes the
customer *"₹X for order Y is on its way back to you, in your account by DD Mon."*
Nothing moves `approved → paid`. There is no Razorpay refund call in any of the six
edge functions, no cron job, and no alert when a refund passes its `expected_by`.
`admin_mark_refund_paid` is a human clicking a button in the console.

Live: 20 refunds, ₹7,155, every one `approved`, the oldest due five days ago. Mock
money — but the machinery is what ships.

Needs, at minimum, an overdue alarm. Ideally a `razorpay-refund` function so the
promise the notification makes is one the platform keeps by itself.

---

### P4 — The gate ships disarmed and nothing couples arming it to the keys

`require_verified_payment` is `false`, and with it false `place_order` accepts any
non-empty string as `payment_id`. The design intent is sound — *"the day the keys
are set as function secrets, every already-installed build starts taking real
payments"* — but arming the trigger is a **separate manual SQL statement**, and
nothing fails loudly if it is forgotten. Between setting the keys and running that
statement, the door is open to anybody holding the publishable key.

Wants a check that refuses to leave the two out of step, or at the very least a
line in `RELEASING.md` that makes them one step.

---

### P5 — Checkout hardcodes "Test gateway — no real money"

[`checkout_page.dart:202`](apps/customer/lib/features/checkout/presentation/pages/checkout_page.dart#L202)
and [`:583`](apps/customer/lib/features/checkout/presentation/pages/checkout_page.dart#L583)
are constant strings. The whole point of the gateway binding is that installed
builds start charging real money with no new release — and those builds will keep
telling the customer no money moves while it does. `RazorpayPaymentGateway` already
receives `configured` from the server; the copy should read it.

---

### P8 — `claim_delivery` ignores the exclusive offer

`available_deliveries` correctly hides an order that has a live offer to somebody
else. `claim_delivery` re-checks status, KYC, online and the cash cap — and
**never looks at `delivery_offers`**. Both are executable by `authenticated`
(verified against `has_function_privilege` on the live database).

So a rider can call the RPC directly and take a job that is mid-45-second exclusive
offer to another rider, who then gets *"Another partner just took that one."* The
dispatch rule is enforced in the read path and missing from the write path.

---

### P9 — `delivery_offers_one_live_per_order` ignores `expires_at`

The index is `unique (order_id) where state = 'offered'` — expiry is not part of
it. `offer_delivery` inserts `on conflict do nothing` and returns null when it
loses, so a stale `offered` row wedges that order's dispatch permanently: every
tick tries, conflicts, and returns null.

Safe **only** because one transaction currently expires offers (step 1 of
`dispatch_deliveries`) and re-offers them (step 2). It becomes real the moment
those are split, or a run errors between the two.

---

### P10 — Smaller items

- **No upper bound on `quantity` in `place_order`.** `v_qty < 1` is refused;
  nothing caps it. `unit_price * quantity` overflows `integer` and surfaces to the
  customer as a raw `integer out of range`.
- **`p_user_phone` is unvalidated** and never checked against the account. It is
  the number the rider calls.
- **The offer countdown trusts the rider's device clock.** `OfferSheet` computes
  `remaining(DateTime.now())` against a server `expires_at`; a phone a minute fast
  closes the sheet the instant it opens.
- **Snackbar fired on a popped route.**
  [`offer_sheet.dart:74-78`](apps/rider/lib/features/jobs/presentation/widgets/offer_sheet.dart#L74-L78)
  calls `_close()` — which pops — and then `ScaffoldMessenger.of(context)`. The
  failure message can be lost or throw.
- **`announce_open_delivery` announces once, forever.** Its guard is "any
  `job_available` notification exists for this order", so riders who come online
  *after* the announcement are never told about the job sitting on the board.
- **The open board leaks addresses.** `available_deliveries` returns `delivery_to`
  and `total` for every dispatchable order to every verified rider, not only the
  ones offered to them.
- **The customer router has no `errorBuilder`.** Any unmatched path renders
  GoRouter's raw developer error page. Not reachable today — `initialLocation` is
  `/` and no route is persisted across launches — but one typo in a push payload
  or a future deep link puts a stack trace in front of a customer.
- **Three hero slides name coupon codes that do not exist.** `TRYNEW`,
  `ZOPIQ150` and `SAVE30` are string constants in `home_hero_carousel.dart`, not
  rows in `coupons`, so a customer who reads one and types it at checkout is told
  the code isn't valid. The file's own header has said so for a while. Either
  issue the codes or rewrite the copy.

---

## Closed

### ~~P11 — Rider pay has no ceiling, and the live payout queue already shows it~~ · migration 0137, 2026-08-24

**Was:** `rider_pay_quote` (0097) is `base_fee + round(km × per_km_fee)` with
nothing bounding `km`. `claim_delivery` freezes it onto the delivery,
`run_rider_payout_batch` sums what is frozen, the console pays what it sums — so
one bad coordinate is an unbounded payout and nothing in between disagrees. The
worst quote on 2026-08-12 was 4,387.5 km → ₹21,962, from three orders carrying an
emulator's Istanbul default against a Rajasthan kitchen.

**The live state on 2026-08-24 was not the one this entry described, and the
difference turned out to be the more interesting half.** Those orders had since
been deleted: `deliveries` held 15 rows whose worst pay was ₹45 over 4.00 km, and
the 24 surviving orders averaged 1.96 km. But **`rider_payouts` 15 still said 4
deliveries, ₹22,737, with exactly one ₹25 delivery still pointing at it.**
`deliveries_order_id_fkey` is `on delete cascade`, so deleting the orders took
the deliveries and left the aggregate standing. The money survived; the evidence
for it did not. Pending queue: 6 rows, ₹22,888, of which ₹22,712 was phantom.

**Fix, in three parts.**

1. **The ceiling is a distance, not a rupee amount.** `rider_pay_rates.max_km`,
   default 30, and `rider_pay_quote` prices `least(km, max_km)`. A rupee cap
   would have been simpler and wrong: the console can already change `base_fee`
   and `per_km_fee`, so a fixed ₹175 quietly becomes an 8.75 km cap the moment
   somebody sets ₹20/km. A distance ceiling survives every rate change and states
   the actual belief — no delivery here is 30 km long, and a number that says
   otherwise is a broken measurement.

   **Why 30**, measured rather than picked: the town lock (0126) means the longest
   legitimate ride is Sadri↔Ranakpur — 8.50 km centre to centre plus both radii
   (6.00 + 5.00) = 19.50 km of crow flight at the geometric extreme, ≈27 km by
   road. It lives on `rider_pay_rates` because a fourth town should be an
   `update`, not a release. `admin_set_rider_pay_rates` was deliberately not
   widened — a third argument creates an overload rather than replacing the
   function, and a rail that only bites at 30 km does not need a weekly knob.

2. **`ride_km` is still returned unclamped.** It is a measurement, and rewriting a
   measurement so the arithmetic beside it reconciles is the worse lie. The
   clamped case is precisely the one where somebody should see 4,387 km next to
   ₹175 and go find the coordinate. 0097's rule that a rider can reproduce the fee
   from the distance printed next to it holds for every ride under the ceiling,
   which is all of them.

3. **A delivery a payout has counted can no longer be deleted** —
   `deliveries_no_delete_when_paid_out`, a `before delete` trigger. This is the
   mechanism that produced payout 15, and it was not the one this entry suspected.
   `admin_delete_order` already refuses to delete an order with money owed back to
   a *customer* and then cascades away a delivery carrying money owed to a
   *rider*. A trigger rather than a fourth check inside that function because the
   console is demonstrably not the only path: `admin_order_deletions` holds 8
   rows, newest 2026-08-08, while the order count fell 55 → 24. It refuses loudly
   instead of adjusting the payout silently — a payout shrinking because an order
   was tidied up is how the number stopped meaning anything.

4. **Every pending payout reconciled to the deliveries that point at it**, written
   as a general statement rather than an update to row 15 so it is checkable
   afterwards. `pending` only: a `paid` payout that lost deliveries is a bank line,
   not a mistake to rewrite. `cash_withheld` untouched — it is discharged by a
   matching `rider_cash_ledger` row, and recomputing it would net the same cash
   twice.

**Verified against the live database:**
- *No real order was repriced.* All 24 orders re-quoted through the new function:
  **0 changed** by the cap.
- *The cap bites where it should.* ZPQ-1141 forced to `route_km = 4387.5` in a
  rolled-back transaction quoted `ride_km 4387.50` and `rider_pay 175` — the
  measurement kept, the pay bounded.
- *A null distance still pays base only.* Coordinates stripped → `ride_km` null,
  ₹25, matching 0097's intent that a kitchen with no coordinates pays the base fee
  and says so.
- *The guard refuses both paths and only the right rows.* A direct delete of a
  paid-out delivery raised; the same order's delete raised through the **cascade**;
  an unattached delivery deleted freely.
- *Grants read from the catalogue:* `has_function_privilege` says neither
  `authenticated` nor `anon` may execute `rider_pay_quote`.
- *The queue is clean:* all 6 pending payouts now equal their deliveries exactly,
  total **₹22,888 → ₹176**.

**Left open deliberately:** the ceiling is not editable from the admin console,
for the overload reason above. When a fourth town makes 30 km wrong, it is one
`update` in psql — or a follow-up that drops and re-creates both pay-rate RPCs.

---

### ~~P6 + P7 — Dispatcher deadlock, and vendor taps stalling behind it~~ · migration 0121, 2026-08-12

**Was (P6):** `dispatch_deliveries` ran every 20 s with no mutual exclusion,
looped up to 50 orders, and `offer_delivery` took a row lock on each
(`update orders set dispatch_started_at = coalesce(…)`) held to commit. The loop
order — `(status = 'ready_for_pickup') desc, created_at` — **changes between
ticks**, because an order moving `preparing → ready_for_pickup` jumps to the
front. Two overlapping runs could lock A→B and B→A.

**Was (P7):** the same row locks meant a cook tapping **Ready** (which opens
`select … for update`) queued behind the sweeper.

**Fix:** two changes, and the second is the one that does most of the work.

1. `pg_try_advisory_xact_lock(4242, 1)` at the top of the sweeper. `try` so a
   tick that finds the board busy leaves rather than joining a queue that grows
   faster than it drains; `xact` so a run that *raises* cannot strand the lock
   and wedge dispatch. The migration also opens an advisory-key registry, since
   there was no convention and a bare one-arg key shares a space with every
   extension on the box.
2. `offer_delivery` reads `dispatch_started_at` before writing it. It was
   rewriting the column to its own value on every tick for ever; now only the
   first pass over an order writes, so an order is locked by dispatch **once in
   its life** rather than every 20 seconds. `coalesce` stays inside the `update`
   — `decline_offer` re-offers inline without the sweeper's lock, so two callers
   can still both read null, and the one that arrives second re-evaluates under
   the row lock it waited for.

**Verified, all three against the live database:**
- *The lock excludes.* Session A took it (`t`), session B was refused (`f`) while
  A held it, and C took it after A **rolled back** — the rollback half is what
  proves a raising run cannot strand it.
- *The sweeper does not block.* `dispatch_deliveries()` returned in 2.5 s while
  the lock was held versus 1.75 s free, both dominated by pooler round-trip —
  against ~8 s if it had waited.
- *The second pass writes nothing.* In a rolled-back transaction, the order row's
  `ctid` moved on the first `offer_delivery` and was **identical** after the
  second. `pg_locks` is the wrong instrument here — row locks live in the tuple,
  not the lock table — so `ctid` is the honest measurement.
- *The function is still intact.* The rewrite touched one block of a 300-line
  function, so it was re-run end to end: it picked a rider, wrote the offer, and
  froze the quote onto it.

**That last check is what turned up [P11](#p11--rider-pay-has-no-ceiling-and-the-live-payout-queue-already-shows-it--migration-0137-2026-08-24)** — the offer it produced was ₹21,962.

---

### ~~Dining and Grocery were dead tabs~~ · 2026-08-12

Not from the sweep — found while answering "what's next" — but the same class of
bug the sweep is full of, and the same one 0119 fixed on the restaurant card: a
control that looks live and is not.

**Was:** branches 1 and 2 of the bottom-nav shell were both `ComingSoonPage`. Two
of five primary tabs went nowhere, and a `BOOK A TABLE` hero slide advertised the
Dining one. Every new customer tapped them once and learned the app was
unfinished.

**Fix:** both branches removed, the pill row rebalanced to Delivery / Gifts, the
Cart branch index moved 4 → 2, the tab-width divisor made a named `_tabCount`
rather than a `4` written twice, the `BOOK A TABLE` slide deleted, and
`coming_soon_page.dart` deleted with its last caller.

**Why cut rather than build:** 3 live restaurants, 179 dishes, 5 riders, 3 towns.
Zomato has Dining because it runs metros with thousands of venues; a table booking
across three restaurants has no supply side, and Grocery is a second logistics
business. Coming back is one commit — a branch, a nav item, and the three places
the tab arithmetic lives, which are now named in each other's comments.

**Verified:** branches read `0 /` → `1 /gifts` → `2 /cart`; `cartBranchIndex`,
`_tabCount` and the nav items agree; nothing persists a branch index, and
`initialLocation: '/'` means no launch can land on a removed route. Analyzer
unchanged at 16 pre-existing issues, none in the touched files.

---

### ~~P2 — The retry after a failed placement charges a second time~~ · 2026-08-12

**Was:** `_attemptKey` is deliberately preserved across a failure so the retry
carries the same idempotency key — and that makes **`place_order`** idempotent,
which is not where the money is taken. The retry re-entered `pay()` first, so a
placement that failed *after* a successful capture sent the customer back to a
button that charged them again. Two captures, at most one order.

**Fix:** `_paidId` on `CheckoutController`, held for exactly the lifetime of
`_attemptKey` and cleared in the same breath — the key names the order that may
already exist, `_paidId` names the payment that certainly does. While it is set
the retry skips the gateway *and* the preflight (whose only job is to stop money
being taken for a doomed order, and the money is already gone) and goes straight
back to `place_order` with the payment it holds.

**Verified:** the mechanism the retry now depends on was confirmed live rather
than assumed — `orders_idempotency_key_unique` is `(user_id, idempotency_key)
where idempotency_key is not null`, and `order_receipt_by_key` returns the
existing receipt for every stored key it was asked about. So a retry is answered
with the order already placed, and now without a second charge behind it.

**Known narrow case, documented on the field rather than hidden:** the notifier
resets on the cart's *subtotal*, so an edit that changes the basket while leaving
the subtotal identical would reuse a payment made for the old one — and two
baskets worth the same can cost different totals, because tax follows each dish's
GST rate. Arithmetically impossible today (every menu item on the platform is at
one GST rate), and when it stops being so the payment gate refuses the underpaid
direction, which lands it in P3 where a payment with no order belongs. Widening
the watch to the whole cart would fix it and would also discard an applied coupon
every time somebody reordered their basket.

**Still not fixed by this:** a payment captured and then lost to a process kill,
or to a cart edit. That needs somewhere to write down a payment that never became
an order — **P3**.

Touched: `checkout_providers.dart` only.

---

### ~~P1 — Pay-then-order has no compensation~~ · migration 0120, 2026-08-12

**Was:** `CheckoutController.placeOrder` ran the gateway first and `place_order`
second, so nine separate rules could refuse an order the customer had already paid
for — restaurant inactive, not accepting, closed, item unavailable, item out of
serve hours, an option withdrawn, coupon expired/capped/spent, address or kitchen
out of area, account blocked, more than ten orders in an hour. With no order row,
`orders_refund_on_termination` (`after update of status on orders`) never fired, so
**no refund was recorded and no notification sent** — the payment simply vanished
into a `verified` intent nothing sweeps.

**Fix:** `checkout_preflight` (migration 0120) asks all of it before the gateway
opens, raising `place_order`'s own sentences. Read-only and unlocked — the coupon
goes through `validate_coupon`, not `coupon_lock_and_price`, so a preflight cannot
hold a popular code for the length of a payment sheet.

**It also fixes a tenth case that was not on the list.** The gateway was asked for
`CartBill.of(cart).total` — computed on the phone — while `place_order` prices in
Postgres and the payment gate refuses an intent worth less than the order. A
one-rupee disagreement in the server's favour was itself a charge-then-refusal.
The preflight returns the server's bill and the app now charges that.

**Verified:**
- Every current-model order repriced through the preflight's arithmetic: **28
  checked, 0 mismatches**, including all 5 discounted ones. (The 27
  `pricing_version = 1` orders predate 0078's tax model and are expected to
  differ.)
- Per-slab rounding is untestable from live data — every menu item on the platform
  sits at one GST rate — so it was exercised synthetically in rolled-back
  transactions: a 5% / 12% / 18% cart matched `place_order` exactly, and **nine
  multi-slab carts under a 37% coupon** (awkward remainders, largest-remainder
  apportionment feeding per-slab rounding) matched on total, tax and discount in
  all nine.
- Grants read from the catalogue, not the migration: `authenticated` may execute,
  `anon` may not.

**Left open deliberately:** the residual window while the payment sheet is on
screen. Closing it needs somewhere to record a payment that never became an order,
and `refunds.order_id` is `not null` with a foreign key to `orders` — so it belongs
with **P3**, not here.

Touched: `supabase/migrations/0120_the_kitchen_is_asked_before_the_money.sql` (new)
and six files under `apps/customer/lib/features/checkout/`.

---

## Not a bug — checked and cleared

Recorded so nobody re-audits them.

- **`razorpay-verify`** — constant-time HMAC comparison, intent matched on order
  id *and* caller, replay-guarded by `status = 'created'` in the update filter.
- **`razorpay-order`** — amount fixed server-side, capped at ₹50,000, user id read
  from the JWT and never from the body.
- **The payment gate itself** (0085 / 0113) — checks existence, `verified`,
  ownership, `amount >= total`, and consumes in the same statement. Sound; it is
  only the *arming* that is owed (P4).
- **Gifts are covered by the gate.** 0113 mirrors 0085 and reads the same
  `payment_settings` flag, so one statement arms both paths. (Earlier notes saying
  otherwise are stale.)
- **Coupon pricing** — `coupon_lock_and_price` takes `for update` on the coupon
  row, `code` is the primary key so exactly one row can match, and
  `least(v_discount, p_subtotal)` makes a payout impossible.
- **Tax apportionment** — largest-remainder per slab; the per-line values sum back
  to the order's exactly.
- **`menu_items` RLS** — insert/update/delete all scoped to `staff_restaurant_id()`.
  The `authenticated` write grants are correctly fenced.
- **Every public table has RLS enabled**, and no table carries an unexpected write
  grant to `anon`.
- **`set_order_status`** — locks the row, enforces the transition table, and
  releases the delivery on cancel/reject.
- **Admin console auth** — `is_admin()` re-asked server-side by every RPC; the
  browser check is presentation only, and fails closed on a network error.
- **`.env.local`** in `apps/admin-web` is git-ignored and holds only publishable
  keys.
- **The customer's `fetchRider` `maybeSingle()`** cannot see two delivery rows: the
  policy restricts to `picked_up`/`arrived_at_customer` and the partial unique
  index allows one live row.
- **Vendor's `.stream()` window** — `.order(desc).limit(200)` is deliberate and
  correct; ascending would pin the window to the 200 oldest orders.
