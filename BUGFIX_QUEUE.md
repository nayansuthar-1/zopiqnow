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

### P2 — The retry after a failed placement charges a second time

`_attemptKey` is deliberately preserved across a failure so the retry carries the
same idempotency key — and that makes **`place_order`** idempotent, which is not
where the money is taken. The retry re-enters `pay()` first. Two captures, at most
one order.

P1's preflight makes the *first* charge much less likely to be wasted, but does
nothing about the retry path once one has happened.

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

### P6 — Latent deadlock between overlapping dispatcher runs

`dispatch_deliveries` runs every 20 seconds with no advisory lock, loops over up to
50 orders, and `offer_delivery` takes a row lock on each of them
(`update orders set dispatch_started_at = coalesce(...)`) that is held until the
transaction commits.

The loop order is `(status = 'ready_for_pickup') desc, created_at` — and **that
order changes between ticks**, because an order moving `preparing → ready_for_pickup`
jumps to the front. Run 1 locks A then wants B; run 2, seeing B promoted, locks B
then wants A. A cycle, and Postgres will break it by killing one of them.

Not firing today: `deadlocks = 0`, and a run averages 0.01 s against 55 lifetime
orders. It is a load-triggered bomb, not an incident.

One `pg_try_advisory_lock` at the top of the sweeper fixes this *and* the
unrelated pile-up when a run ever exceeds its 20-second period.

---

### P7 — Vendor taps stall behind the dispatcher

Same root cause as P6, milder and more visible: the sweeper holds row locks on up
to 50 orders for its whole transaction, and `set_order_status` opens with
`select … for update` on one order. A cook tapping **Ready** blocks until the sweep
commits. Invisible at 55 orders; a complaint at 5,000.

Closed by P6's advisory lock plus keeping the sweeper's transaction short.

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

---

## Closed

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
