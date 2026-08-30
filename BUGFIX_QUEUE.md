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

### P12 — A vendor sets the GST slab their own food is taxed at

`menu_items` is the one table `authenticated` may write, correctly scoped by
`staff_restaurant_id()`. The `update` policy names no column list, so it covers
`gst_rate_bps` and `hsn_code` alongside price and availability, and
`place_order` reads the slab straight off the row.

`menu_items_gst_rate_is_a_real_slab` limits it to `{0, 500, 1200, 1800}`, so the
worst case is a kitchen moving its food to 0% and the platform under-collecting
the GST it is liable for under s.9(5). Every one of the 1,190 live items is at
500 today.

**Deliberately not fixed.** 0% is a real slab and some food genuinely sits at it,
so this cannot be a constraint; and the vendor is arguably the right party to
classify their own dishes. It is a column-level `grant` decision or an
approval flow, which is a product question rather than a bug. Recorded so the
answer is a decision rather than an oversight.

---

### P13 — The gift bag never accounts for the tax inside its delivery fee

`gift_bag_quote` returns `total = subtotal + delivery_fee + taxes` and splits
`cgst`/`sgst` over `taxes` alone. The food path extracts the GST sitting inside
its gross fees (`tax_on_fees`, `f × r / (10000 + r)`) and includes it in the
split; the gift path has no such column and does not.

**No live impact:** `gift_settings.delivery_fee` is ₹0, so there is nothing
inside to extract. It becomes a real under-declaration the day somebody sets a
gift delivery fee in the console, which `admin_set_gift_delivery_fee` allows in
one call.

---

### P14 — The vendor's Earnings screen and their statement will not agree

`vendor_earnings_summary` computes `net_earnings = (gross − own_offers) −
commission`. `run_settlement_batch` computes `net_payable = (gross − own_offers)
− commission − refunds + adjustments`. So a restaurant that has funded a refund
reads one number on the Payments screen and is paid a smaller one, with nothing
on either screen explaining the gap.

Defensible as written — the screen is a live earnings figure and the statement is
a payout — and the entity doc says so. It is still the single most likely vendor
support call on that screen, and the fix is small: carry `refunds` in the summary
and label it the way the statement does.

---

## Closed

### ~~P8 — `claim_delivery` ignores the exclusive offer~~ · migration 0148, 2026-08-29

**Was:** `available_deliveries` hid an order that was mid-offer to somebody
else; `claim_delivery` re-checked status, KYC, online and the cash cap and never
looked at `delivery_offers` at all. Both are executable by `authenticated`, so a
rider could call the RPC directly and take a job out from under another rider's
exclusive ring. The dispatch rule was enforced in the read path and missing from
the write path.

**Closed by 0148**, the relay-and-contest migration, which needed the same guard
for its own reasons and this entry never recorded. `claim_delivery` now refuses
with *"That job is with another partner right now. If they pass on it, it comes
back to you."* when a live offer belongs to somebody else.

The guard is deliberately not "only the offer holder may claim". It admits both
`offered` **and** `expired`, which is 0148's rule: your fifteen seconds are
exclusive, but when they lapse the job stays on your board rather than vanishing
from it, and two riders reaching for the same order inside `contest_seconds` are
settled by distance in `resolve_delivery_contest`. A rider who was never offered
the job is the only one the guard turns away while the ring is live.

---

### ~~P9 — `delivery_offers_one_live_per_order` ignores `expires_at`~~ · migration 0150, 2026-08-30

**Was:** the index is `unique (order_id) where state = 'offered'` and cannot be
anything else — `expires_at > now()` is not immutable, so no partial index will
carry it. A row that had lapsed but was not yet *marked* lapsed therefore still
held the slot, `offer_delivery`'s `on conflict do nothing` lost to it and
returned null, and every tick after lost to it again.

**Reproduced before fixing**, on a borrowed order in a rolled-back transaction:
with one stale `offered` row in place, three consecutive `offer_delivery` calls
returned null while three other eligible riders sat idle. The control run, with
no stale row, offered on the first call.

**Why it had never fired:** `dispatch_deliveries` expires the whole board one
statement before it re-offers, in the same transaction, so the sweeper never
meets its own stale rows — and the only other caller, `decline_offer`, marks its
own row `declined` before calling in. Note that the queue's original wording was
wrong about one of these: a run that *errors* between the two statements does not
wedge anything, because the whole sweeper is one transaction and the error rolls
the expiry back with it. The real exposure was always the other half — that the
guarantee lived in two callers' statement ordering rather than in the function
depending on it.

**0150** moves it into `offer_delivery`: one `update`, scoped to the order being
offered, expiring its own lapsed row before it tries to insert. The function no
longer trusts its callers to have cleared the path. `dispatch_deliveries` keeps
its board-wide expiry — not redundant, that is what takes a lapsed offer off a
rider's screen for orders this function never reaches.

The body was taken from `pg_get_functiondef` on the live database rather than
from 0148's file, so what was replaced is what was actually running; the diff
against live is the new block and nothing else.

**0148's rule verified intact** after the change: the rider who let the offer
lapse keeps their row (marked `expired`, not deleted), is not re-offered by the
candidate query, and `claim_delivery`'s guard still lets them claim. A third
rider who was never offered the job is still refused while the ring is live.

---

### ~~P3 — Refunds are promised with a date and nothing pays them~~ · migrations 0138 + 0149, 2026-08-30

**Was:** `orders_refund_on_termination` inserted the refund already `approved`,
pushed the customer *"₹X for order Y is on its way back to you, in your account
by DD Mon."*, and then nothing moved it. No Razorpay refund call in any edge
function, no cron, and no alarm when `expected_by` passed.
`admin_mark_refund_paid` was a person clicking a button.

**Closed in two halves, three weeks apart.**

*The paying* was 0138 (24 Aug), and this entry was stale in never recording it.
`pay_approved_refunds` runs every five minutes, hands each approved refund to
Razorpay through `pg_net`, and collects the answer on the following tick —
`paid` with the `rfnd_…` reference on a 200, `failed` with Razorpay's own
words otherwise. It claims a row into `processing` before firing, so two
overlapping ticks cannot pay one refund twice, and it never retries a call that
was never answered. Verified live: **3 refunds paid by it, 1 refused.**

*The watching* is 0149 (30 Aug), and it is what P3 actually asked for.
`sweep_stalled_refunds` runs every fifteen minutes and keeps one standing
`refunds_stalled` alert on the console's Alerts page while any refund is
`approved` past `expected_by`, `processing` for over thirty minutes, or
`failed`. One alert and not one per refund: the per-item queue is already the
Refunds page, and a second copy of it would be worked in one place and cleared
in the other. It clears itself — `resolved_by = 'system'`, with the 0092 audit
row to match — the moment the queue empties.

The Alerts page was rider-shaped and is now kind-aware. It had been rendering
*"0 in the last week"* and a **Suspend this rider** button on any alert that was
not a no-show, which the five `orphan_payment` alerts from 0142 had already
been hitting.

**What the first run found — the remaining work, and a person's:** 19 refunds,
₹4,640, 18 of them past the date the customer was promised, the oldest due
**10 August**. Every one names a `pay_mock_…` capture — taken before Razorpay
existed, so no money was ever captured for them and none can be sent back.
`pay_approved_refunds` skips them by design and 0138 left them "for a human to
decide about"; until 0149 there was nothing to tell the human they were waiting.
The decision — `declined` with a reason, or settled outside the gateway —
belongs to whoever knows what those testers were told.

**Still owed, and named in 0138's own header:** a `refund.processed` webhook. A
200 from Razorpay is recorded as `paid`, but the API answers `processed` *or*
`pending`, so a refund whose bank has not confirmed yet reads as done a little
early.

---

### ~~Money sweep 2026-08-29 — five more, found by walking the rupee end to end~~ · migration 0141

A pass over the whole money path — cart, preflight, gateway, `place_order`,
refunds, settlements, rider payouts, gifts, and the console's own arithmetic.
The healthy majority is worth recording because it is what made the exceptions
findable: every money table is `select`-only to `authenticated` and written
exclusively through `security definer` functions; all 106 `admin_*` RPCs call
`assert_admin()`; every amount is whole rupees with the paise conversion in
exactly three places; and `CartBill`, `checkout_preflight` and `place_order`
agree to the rupee, largest-remainder rounding included.

**1. An order with any earlier refund could never be cancelled.**
`orders_refund_on_termination` refunded `new.total` and `refund_within_the_order`
refused anything past the order's total, so the two collided:

    update orders set status = 'cancelled' where id = 'ZPQ-1166';
    ERROR:  That would refund ₹342 on an order of ₹292 — ₹50 of it is already refunded.

The whole statement aborts, so the order most likely to need cancelling was the
one nobody could cancel — not the customer, not the kitchen, not an admin. Now it
refunds the *balance*, and stands down silently when nothing is left owing.

**2. A refund that failed left the restaurant paying for it.** A vendor-funded
refund is charged to the open statement on approval; when Razorpay refused it and
`pay_approved_refunds` moved it to `failed`, the trigger saw `settlement_id is not
null` and returned early. Proven live: settlement 20 went `refunds 250 → 350` on
approval and stayed at 350 after the failure. The customer got nothing back and
the restaurant was still short ₹100. Now reversed — in place while the statement
is `pending`, and as an admin alert asking for a credit on the next one when it
has already been paid out.

**3. Two refunds at once could jointly exceed the order.** `refund_within_the_order`
read the order and its existing refunds without a lock. One `for update` on the
order row.

**4. Cancelling a paid gift order kept the money and said nothing.** Gifts are
prepaid and have no refund ledger — 0116 removed it deliberately — so an admin
cancel wrote no refund row, sent no notification, and left no record that money
was owed. *"Gifts are final"* is a rule about what the customer may call off; it
was never a licence to cancel and keep the payment. The ledger stays out. A cancel
now requires a reason, raises a `gift_refund_owed` alert naming the amount and the
Razorpay id, and tells the customer their money is coming back.

**5. The console's commission tile overstated the platform's cut.** It charged
commission on the full `subtotal` while `run_settlement_batch` charges it on
`subtotal - vendor_funded_discount` — despite a comment claiming the two were the
same arithmetic. No live divergence yet (every coupon on the platform is
platform-funded, so the vendor-funded discount is ₹0), so this is preventive: it
would have started lying the first time a restaurant ran its own offer.

Also in 0141: a sweep flagging verified payments that never became an order —
money captured with nowhere in the schema to record it, which is the residue of
pay-then-order that P1's preflight narrowed but could not remove — and the
`PUBLIC` execute grant revoked from the three argument-less trigger functions
0087/0089/0091 missed.

---


### ~~P4 — The gate ships disarmed and nothing couples arming it to the keys~~ · migration 0141, 2026-08-29

**Was:** `payment_settings.require_verified_payment = false`, and with it false
`orders_require_verified_payment` returns on its first line — so `place_order`
accepted any non-empty string as `payment_id`.

**What made it urgent rather than theoretical:** the keys went in on **25 August**
and the statement was never run. `razorpay-order` had been answering
`configured: true` for four days, the mock fallback was unreachable, payments were
going through it (ZPQ-1185…1189), and the door this item describes was open the
whole time. Anybody signed in could call `place_order` over PostgREST with
`p_payment_id: 'anything'` and eat for free. The app was never the attack surface;
the RPC is, and it is `authenticated`-executable by design.

**Severity, stated honestly:** the keys are `rzp_test_…`, so **no real money has
moved** and nothing was being stolen. What those four days demonstrate is exactly
what this item predicted — arming is a separate manual statement and nothing fails
loudly when it is forgotten. Armed now so that switching to live keys is one step
instead of two.

**Now:** armed. Verified against the live schema, every case rolled back:

| case | result |
|---|---|
| paid the right amount | order placed, intent `consumed` and linked to it |
| fabricated payment id | *We couldn't confirm your payment.* |
| ₹1 paid for a ₹207 order | refused — `intent 54 paid 1 for an order of 207` |
| another customer's verified payment | refused — `belongs to another customer` |
| same payment spent twice | first placed, second refused — `is consumed, not verified` |
| honest retry, same idempotency key | same order id returned, one row written |

**What arming it exposed** — migration 0142. Marking an intent `consumed` is the
gate's *other* job, and it had not been doing that either. So the five real payments
taken since 25 August were still sitting at `verified`, and the moment the gate
started honouring `verified` rows each became a live single-use voucher worth up to
its own amount — ₹9,930 on the largest. Backfilled to `consumed` against the orders
they actually bought.

The automatic coupling this item asks for still does not exist. What exists is that
the statement has been run, and the disarm command is written into 0141's header.

---

### ~~P1a — `place_order` cannot be called twice in one transaction~~ · migration 0143, 2026-08-29

**Was:** `create temp table _lines (…) on commit drop` drops at commit, so a second
call inside the same transaction died with `relation "_lines" already exists`.

Found again from the other end: this is what stopped the P4 double-spend test above
from reaching the payment gate at all. A function whose failure mode is *"you may
not test me twice"* is one nobody can be confident about, which is the cost this
item predicted.

**Now:** `to_regclass('pg_temp._lines')` and an explicit drop — chosen over
`drop table if exists`, which raises a NOTICE every time it skips: once per order
placed, forever, in the logs and on the wire to PostgREST. `on commit drop` stays,
because it is still what cleans up in the ordinary single-call case.

---

### ~~P5 — Checkout hardcodes "Test gateway — no real money"~~ · already closed in code

Stale entry, cleared on inspection.
[`checkout_page.dart:591`](apps/customer/lib/features/checkout/presentation/pages/checkout_page.dart#L591)
now reads *"Pay online · UPI, cards and more · secured by Razorpay"*, and its own
doc comment says why the old string went: *"copy that outlives the thing it
describes is how a customer gets told no money moves while it does."* Recorded here
so the next sweep does not re-find it.

---


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
