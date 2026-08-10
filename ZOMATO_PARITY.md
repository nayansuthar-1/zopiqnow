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
- [x] `supabase functions delete send-order-push` ✅ **DONE** — verified 2026-08-07 by
      calling it: `POST /functions/v1/send-order-push` → **404**, while
      `send-notification` → 403 (deployed, refusing an unauthenticated caller). The
      local source folder is all that remains of it. ~~The superseded function is still~~
      ACTIVE beside `send-notification`, and a dead endpoint nobody calls is one
      somebody wires back up. Unwired since 0058 dropped `on_new_order_push`, so this
      is a deployment to remove, not a behaviour to change. **The source folder stays
      until the deployment goes** — a live function with no source in the repo is the
      same hazard pointing the other way
- [x] Commit the rider in-app notification inbox ✅ **DONE 2026-07-30** (`1c8d9e6`).
      It was worse than "uncommitted": `jobs/home_page.dart` had been importing
      `notification_bell.dart` and `rider_animations.dart` since `9e45fa8`, so the
      rider app had not compiled from a clean checkout for two phases. The same
      commit fixes push registration — 0060 dropped the two-argument
      `register_device_token` and the committed rider was still calling it, so every
      rider device registration was failing against the deployed database — and
      removes the stray `apps/rider/lib/lib/app/rider_shell.dart`, which was the only
      analyzer *error* in the app

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

✅ **DONE — verified 2026-08-07.** It was built after B4, exactly as this note planned.

- [x] `refunds` table + state machine (requested → approved → paid), FK to the order
- [x] Refund on cancel-after-payment and on vendor rejection
- [x] Customer: order issue / report screen, feeding a support queue —
      `order_issue_section.dart`, `order_refund_section.dart`, `report_issue_sheet.dart`,
      backed by `support_tickets`
- [x] Admin: refund management console — `apps/admin-web/src/payouts/RefundsPage.tsx`

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

### B4 — Payments, for real ✅ *built (migrations 0085–0086) — **not yet armed***
- [x] Razorpay checkout — `razorpay_flutter: 1.4.5`, pinned
- [x] Server-created payment order — edge function `razorpay-order`; the client never
      names an amount
- [x] **Signature verification** server-side — edge function `razorpay-verify`, HMAC
- [x] Payment status on the order; a failed payment must not create a half-order —
      `payment_intents`, plus the 0086 idempotency key so a retried checkout cannot
      place a second order
- [x] Refund path wired to B2

⚠️ **The gate is built and switched OFF, and that is the last thing standing between
this repo and taking real money.** Verified against the live database on 2026-08-07:

```
require_verified_payment = false
razorpay keys in vault   = 0
```

`orders_require_verified_payment` (0085) is a `before insert` trigger that consults
`payment_settings`. Until the flag is true, an order can be placed without a payment
having been proved. Turning it on before Razorpay keys exist would stop the product
taking orders at all — which is why it ships off — so the order is: **keys into Vault
first, then one statement.**

```sql
update public.payment_settings set require_verified_payment = true;
```

- [x] **The gate covers gifts too** — migration **0113**, applied 2026-08-10.
      The statement above now arms **both** paths.

`orders_require_verified_payment` was a trigger on `orders` alone; `gift_orders` had
exactly one trigger and it was the audit one, so `place_gift_order` took
`p_payment_id` entirely on trust — never checked against `payment_intents` or against
Razorpay. Arming the flag would have left the gift path exactly as open as it was.
Found by the 2026-08-09 sweep (B8) and **not** fixed by 0112, which is about charging
the right amount rather than proving it was charged; the second job needed
`payment_intents` to learn about `gift_orders`, which is a schema question and not a
flag. 0113 is that schema change:

- `payment_intents.gift_order_id`, beside `order_id`, with a check constraint saying
  an intent is spent on one thing or the other and never both. Not a reused
  `order_id`: everyone who touches that column reads it as `orders.id`, and a `ZPG-…`
  sitting in it would join to nothing while looking like it should.
- `gift_orders_require_verified_payment`, a `before insert` trigger in the same shape
  as 0085's — verified, unconsumed, same customer, `amount >= total`, one opaque
  sentence for every refusal and the detail in the log.

**One flag, not two, and one table, not two.** Two booleans would be two things to
remember on the day the keys land, and the forgotten one is the one nobody is looking
at. Two intent tables would be two ledgers holding the same Razorpay payment id, each
satisfied and neither wrong on its own — so a single `status='consumed'` transition on
a single row is the only thing that can stop one payment buying a dinner *and* a gift.
That case is checked, not assumed: the run below spends an intent on a gift and then
watches 0085's own gate refuse the food order that names it.

**No `payment_method` branch, unlike 0085.** `gift_orders.payment_method` is pinned to
`'upi'` by a check constraint (0096, following 0084), so the branch would be dead code
— and leaving it out is the safe direction: if that constraint is ever widened, the
gate applies to the new method until somebody decides otherwise instead of silently
exempting it.

**Nothing to build on the device, on either platform.** Gift checkout has gone through
the same `paymentGatewayProvider` as food since 0112, so the day keys exist a gift
payment produces a verified intent exactly as a dinner does; the refusal sentence
already reaches the screen through the gift datasource's `P0001` mapping. The
app-visibility half of the payment path was checked on both and needs nothing: iOS
declares the UPI schemes in `Info.plist`, and Android gets `scheme="upi"` from the
Razorpay AAR through the manifest merger — read out of the **merged** manifest, not
the source, which is the same lesson the release-APK permission check learned.

**15 edge cases, run against the live database in a rolled-back transaction** before
applying. Flag off: a fabricated reference still places an order, exactly as before.
Flag on: fabricated, unverified, another customer's, and a rupee short are all
refused; a rupee over is placed, because overpayment is a refund and not a reason to
withhold somebody's parcel; the happy path consumes the intent and stamps
`gift_order_id`; the same intent a second time is refused; an idempotent retry returns
the same order and spends only one payment. Structure too — no overload (0051), the
search_path pinned, the trigger body executable by neither `anon` nor `authenticated`
(0093), and the check constraint refusing both order columns at once.

---

### B5 — Communication ✅ **DONE 2026-07-29** (migration 0061)
- [x] Customer → rider call. `url_launcher` moved from transitive to direct in the
      customer app at the version the root lockfile already froze — **not one new
      version** (Rule 3), plus the `tel:` `<queries>` entry the rider app has had
      since 8g. Masked numbers are still owed and are a vendor contract, not a button
- [x] Customer → restaurant call, on the order screen while the order is live
- [x] Rider → restaurant call. One button whose *target* switches with the job —
      the kitchen while collecting, the customer while carrying, the same rule the
      map pin follows, so the two can never point at different people
- [x] Customer ↔ rider chat, canned. Realtime thread, read receipts, a push each way
- [x] **Delivery instructions** — on the address, prefilled at checkout, overridable
      for one order, frozen onto the order, printed on the rider's card while carrying

**The database owns the words.** "Canned messages" means nothing if an app decides
what a code says: the app would be free to put any sentence under any button. So
`order_message_body(sender, code)` is the only place the twelve sentences exist,
`order_message_menu()` hands each caller *its own* half of the list (the role is
derived from the caller, never passed), and `send_order_message` writes the body it
looks up rather than one it was given. Two copies of the list would be two lists, and
the day they drift is the day somebody taps "Leave it at the door" and sends "Thank
you!". The body is then *stored* on the row beside the code, so rewording a line next
month cannot rewrite a conversation that already happened — `order_items.name`'s
argument about a renamed dish.

**The window is the one the customer already had.** A thread opens at `picked_up` and
closes at `delivered` — precisely the states 0049 lets a customer see their rider in.
Earlier, the rider may still drop the job and the customer has not been told their
name; later, the job is over and the rider's number is theirs again (0039's rule).
The rider's `delivery_notes` and `customer_phone` both go null at `delivered` for the
same reason: a note is the customer's description of their own front door.

**`revoke all`, on a table this time.** Supabase's default privileges grant `anon` and
`authenticated` insert/update/delete on every new table in `public`, so `order_messages`
arrived writable and a bare `grant select` added nothing. RLS would still have refused
the write for want of a policy — but "no policy exists yet" is a weaker guarantee than
"no grant exists", and the next migration to add an insert policy for one purpose would
have silently opened all three. Found by reading the grants back in the rolled-back
dry run, not by assuming. That is 0045's lesson applied to a table.

**Two things deliberately not built.** No masked numbers — a `tel:` to the real number
is what this platform can honestly do today, and masking is a provider with a contract
behind it. No vendor side of the chat: a kitchen with a headset is a support product.

---

### B6 — Ratings, reviews, invoice, offers ✅ **DONE 2026-07-29** (migrations 0062–0065)
- [x] `reviews` table — keyed by **order id**, not by (customer, restaurant): reviewing is
      something you do to a *meal*, so ten orders earn ten reviews and one order never
      earns two. Editable for an hour, frozen by a trigger after that
- [x] Customer: rate the food and the rider **separately**, from the receipt. Two rows of
      stars because they are two people's work, and the rider's row is nullable — null is
      "no opinion", not a zero dragging somebody's average down
- [x] Vendor: Reviews room, with the histogram and the order id, and **never the customer**
- [x] Rating recomputation as a trigger on `reviews`, the only writer of either `rating`
      column. `delivery_partners` gains the two the restaurant has had since 0001
- [x] **Digital invoice** — GST-shaped, `pdf` + `printing` (an approved Rule 3 request),
      one series per restaurant per financial year, issued on delivery
- [x] Vendor-created offers — `coupons.restaurant_id` (null = platform), scope enforced in
      `validate_coupon`, an Offers room for the owner, the struck-through total for the
      customer

**No app ever writes a rating.** `restaurants.rating` has been a column since 0001 and a
*fiction* since 0001 — a number typed into a seed file next to a `rating_count` of 0. The
fix is not "let the app PATCH it": an aggregate a client can set is not an aggregate, it is
a claim. `reviews` is the only writable thing, `submit_order_review` the only way to write
it, and a trigger recomputes the figure from the rows underneath. There is no code path
anywhere that raises a restaurant's rating without a delivered order behind it.

**The seeded numbers survive until a real one replaces them.** The recompute is guarded by
`agg.n > 0`, so a kitchen with no reviews keeps what it was seeded with rather than
dropping to "0.0 ★" — a lie in the opposite direction — and can never get the seed back
once a real average takes over.

**An invoice is a document, not a view of a row.** So it gets the two things a row has
never had: a number that is never reused, and the papers of the seller. It is issued on
`delivered` and not on `placed`, because a statutory series must not have gaps and an order
that gets cancelled never became a supply. One series per restaurant per financial year —
the kitchen is the supplier, so the kitchen's series is the one that has to be consecutive.
Not one figure moves: the tax an order was charged is the tax the invoice states, split
into halves and labelled. A migration that "corrected" the GST treatment of orders already
placed would be rewriting receipts.

**The offer's scope is a `where` clause, not a screen.** A code belonging to another kitchen
is answered with the same "isn't valid" as a code that never existed — a distinct message
would be a way to enumerate competitors' promotions. `coupons` also lost the default
insert/update/delete grants it had carried since 0003: RLS with no write policy had been the
only thing between a stranger and a 100%-off code, and "no policy exists yet" is weaker than
"no grant exists". The world-readable policy narrowed to platform codes only.

**And 0065, because the grants in 0062–0064 were decorative.** Postgres grants `execute` on
every new function to `PUBLIC`, so `grant execute … to authenticated` added nothing — the
function was already callable by `anon` the moment it was created. Read back off the live
database rather than assumed, exactly as 0061 found the same thing about a table. Everything
this phase added is now revoked and re-granted to the caller that needs it: the two constants
and three trigger bodies to nobody, `restaurant_reviews`/`restaurant_offers` to `anon` too
(browsing has never required an account), the rest to `authenticated`. `anon` can read a
restaurant's wall and cannot write to it — checked with `has_function_privilege`, not by
reading the migration back.

---

### B7 — Admin panel completion ✅ **DONE 2026-07-29** (migration 0066)
Everything the console could do until now was *setup* — onboard a restaurant, add a
rider, write a hero slide, settle last week's rider pay. None of it was about today.
An order going wrong right now was invisible to ops, and the only lever anybody had
over it was a `psql` prompt.

- [x] **Live order monitoring** — every open order, oldest first, with the kitchen, the
      rider and what they are doing, the offer in flight and its countdown, the ETA and
      the sentence explaining it. `/` is this screen now; Restaurants moved to
      `/restaurants`, one click away
- [x] **Coupon management** — platform codes are writable at last (they have been seed
      data since 0003), restaurant offers are listed read-only beside them
- [x] **Push notification panel** — one message to an audience, the reach shown as a
      number *before* the send, and every send recorded in `broadcasts`
- [x] **Platform analytics** — orders, GMV, commission, discount, cancellation rate,
      what is live right now, a daily chart and the busiest kitchens
- [x] **Vendor settlement reports** — `settlements` has been rolled up every Monday
      since 0017 and read by nobody but the vendor. Same shape as rider payouts, down
      to the mandatory UTR
- [x] **Admin force-abandon / support override** — the gap 8b-4 named and would not
      guess the shape of

**The override is two levers, not one.** 8b-4 left this open because *"inventing its
shape here would be guessing"*. The shape it took: **release** takes the order off its
rider and puts it back on the shelf, and **cancel** ends it. A rider who has gone dark
and an order that has to be called off are different problems, and one button would
have had to guess which was happening. Both refuse a blank reason — an override is the
one action in this system with no predicate behind it, allowed because a person said
so, and the sentence is the only thing that makes it auditable afterwards. A cancel
is refused once an order is `delivered`: 0063 issued an invoice out of a gapless
series, and cancelling behind it would leave a statutory document describing a supply
that never happened. That case is a refund (B2b) — a second document, not the erasure
of the first.

**Release puts an `out_for_delivery` order back to `ready_for_pickup`**, because
`dispatch_deliveries` only looks at `preparing` and `ready_for_pickup` and would
otherwise never come looking. `ready_for_pickup` and not `preparing` because that is
what is true — the food was cooked and packed. Whether it needs cooking *again*, the
released rider still having the bag, is a judgement about the real world that no
predicate can make, so the kitchen is told and decides.

**The bug this phase existed to find.** 0040 promised a rider could not be switched
off while carrying an order, and checked `state in ('claimed','picked_up')` — the whole
set on 2026-07-22, and two-thirds of it since 0049 added `arrived_at_restaurant` and
`arrived_at_customer`. For five phases a rider standing at the customer's door read to
the console as free and the switch that was meant to be refused was offered. Both
functions now say it negatively: a delivery is live unless it is `delivered` or
`cancelled`. **A positive list of live states goes stale the next time somebody adds
one; the negative list cannot.**

**And what fixing it uncovered.** A `deliveries` row sitting at `arrived_at_customer`
under an order that reached `delivered` by some other route back in B1 — a job that
ended and never closed its own row. Invisible under the old list; under a corrected
list *and nothing else* it would have pinned its rider to the roster as permanently
carrying and refused every attempt to switch them off, for ever. So "live" is the
conjunction it always meant: this delivery has not ended **and** the order it belongs
to has not either. True of every orphan, not just the one that exists today. The row
itself is left where it is — closing it would move it into the next Monday's payout
batch, and **paying somebody is not a data repair**.

**The console polls, and says so.** Every other live surface here is on Realtime, which
this screen cannot use: `orders` grants an admin no read at all, `admin_orders` is a
`security definer` function, and a function cannot be subscribed to. An admin policy on
`orders` would buy a socket at the cost of the console's one structural guarantee —
that it reaches the database through named functions and nothing else. Fifteen seconds,
a visible clock, a refresh button. An ops screen at a desk can afford to be a
quarter-minute behind; it cannot afford to be the reason a table got a read policy.

**A broadcast is not a new mechanism.** 0047 built one path from a `notifications` row
to a phone; a broadcast is that path walked many times, one row per recipient, because
an inbox belongs to a person and a shared row would have no owner and no read receipt.
It is the most public thing the console can do and it has no undo, so: the reach is a
number on screen before the send, the send needs a second click against that number,
and the database refuses the identical message twice inside five minutes — which is the
realistic accident, not a wrong audience.

**A coupon bug the edge-case run caught before it shipped.** The first cut of
`admin_save_coupon` copied 0064's normalisation, which strips everything but letters
and digits. But a vendor code *is* `<restaurant id>-<suffix>` — the hyphen is
structural — so `R1-SUMMER` normalised to `R1SUMMER`, a code that does not exist, which
the ownership check therefore could not see, and which was cheerfully created as a new
platform coupon. Hyphens survive the strip now, and the reserved prefix is stated out
loud rather than left implied: `<restaurant id>-…` belongs to that kitchen whether or
not a code is there yet.

**28 edge cases, run against the live database in a rolled-back transaction**, and
three of the first failures were the *test* being wrong rather than the code — RLS
hiding `coupons`, `orders` and `notifications` rows from an `authenticated` reader
exactly as designed, and `delivery_codes` refusing the read outright (0049). Every
refusal read back as a sentence; all 18 functions refused a signed-in non-admin with
"You are not a Zopiqnow admin."; `anon` can reach none of them; `broadcasts` arrived
with RLS on, no policies and no grants (0061's lesson, applied without having to learn
it again); and no overload was created (0051's).

---

### B8 — Hardening (runs last, but the rules apply from B1 onward)
- [x] Rider identity verification / KYC — migration **0080**; documents gate five work
      paths, expiry recomputed rather than stored
- [x] Fraud: velocity limits, a cap on concurrent claims, OTP attempt caps — migration
      **0090** (10 orders/hr, 6 broadcasts/hr, 20 chat lines per side)
- [x] `/security-review` over every new RPC and policy — the AUDIT_REPORT_2026-07-30
      pass and the remediation queue behind it
- [x] **`revoke all on function X from public, anon, authenticated`** on every ops-only
      function — migration **0093**. The 0045 lesson, and the sharper one behind it:
      there are *two* routes in, PUBLIC **and** a default grant to `authenticated`, so
      revoking from PUBLIC alone leaves it open
- [x] **Release-APK manifest check for every app** — read out of the built APK with
      `aapt2`, not off the manifest source. The customer app declares 4 permissions and
      ships 16; the extra 12 arrive through the manifest merger
- [ ] Edge-case matrix per phase, run against the live DB in a rolled-back transaction
      — *a standing practice, never "finished"*. **Last swept 2026-08-09, over
      0094–0111** — the eighteen migrations that had shipped since the audit that
      closed this item's sibling above. What the sweep read off the live database
      rather than off the migrations:
      - Every `security definer` function in `public` pins `search_path`. No
        exceptions, so 0093's rule has held through eighteen migrations.
      - **No overloads anywhere in `public`** — 0051's lesson, still true.
      - `anon` can execute five application functions: `serviceable_point`,
        `delivery_area_check`, `menu_item_is_servable_now`, `restaurant_reviews`,
        `restaurant_offers`. Every one is a browsing surface and intended. The
        other 33 `anon`-executable functions are `pg_trgm`'s own.
      - All 52 tables have RLS on. The only write grants to `authenticated` are
        `addresses`, `favourites` and `menu_items` — the last scoped to
        `restaurant_id = staff_restaurant_id()` on insert, update *and* delete.
      - 27 refusals checked by calling them: `anon` reaches none of the gift,
        support-ticket, admin-menu or order-photo surfaces; a signed-in
        non-admin gets *"You are not a Zopiqnow admin."* from all 15 admin
        functions added since 0093; `my_order_issues` is scoped to `auth.uid()`.

      **And one thing it found.** See the gift bag, below.
- [~] Perf: rebuild/scroll profiling on the Android 10 floor, pagination, image caching
      — **the caching half is done (2026-08-09); the other two stand as written:**
      - [x] *Disk image caching* — `ZopiqDiskImage`, an `ImageProvider` over an
        on-disk store, behind the `ZopiqNetworkImage` every call site already uses.
        Nothing in feature code changed. `ZopiqNetworkImage` already decoded at draw
        size (`cacheWidth`); what was missing was survival across a restart, and
        every food photo being re-downloaded on every cold start is the part that
        actually costs a customer money on Indian mobile data.
      - [ ] *Pagination* is premature. The feed loads every nearby restaurant and there
        are ten of them; `.range()` on ten rows is complexity bought against a problem
        that does not exist yet. Revisit at a few hundred.
      - [ ] *Profiling* wants an Android 10 device, and the one on the desk is Android 13.

**The dependency question this item had been parked on turned out to have a third
answer.** It was written as a choice between taking `cached_network_image` — a new
package, and therefore an approved Rule 3 request — and shipping without disk caching.
But `crypto` and `path_provider` were **already in the root lockfile as transitive
dependencies**, at 3.0.7 and 2.1.6, so `zopiq_ui` declares them at the versions already
frozen and the whole feature costs **no new package and no moved pin**. Proven, not
asserted: `pubspec.lock` is byte-for-byte identical after the resolve. The same
transitive-to-direct move `url_launcher` made in B5 and `http` made for the profile
upload.

**The cache directory is the OS *cache* directory, not documents.** Android and iOS are
both free to delete it under storage pressure, which is exactly the contract a cache
should have — the alternative is an app that quietly grows a private hoard the system
cannot reclaim when the phone fills up.

**Three things that would each have been a bug, written down because none is obvious
from the feature description:**
- *A partial write must never be readable.* Bytes go to `<name>.part` and are renamed,
  because a rename is atomic. A truncated file that decodes is worse than no cache: it
  is a corrupt photo on every launch from then on, with nothing to invalidate it.
- *Two decode widths for one URL are two cache keys.* The rail draws a dish small and
  the detail sheet draws it large, so `ResizeImage` produces two providers — which
  without an in-flight map is two downloads racing to write one file. Deduplicated on
  the URL, which is the thing that is actually the same.
- *A failure must not be cached.* On error the key is evicted from the memory cache in
  a microtask, so the next build is free to try again rather than being handed the same
  error for the life of the process. That is what `NetworkImage` does, for this reason.

**And a ceiling, because an unbounded cache is a bug with a long fuse:** 50 MB and 30
days, swept once after the first frame in the customer and vendor apps. There is no LRU
touch on read — a disk write on every image draw costs more than the occasional
re-download of a photo that is genuinely still in use.

**Not yet seen on a device.** `flutter analyze` is clean in all three apps and the
customer and rider debug APKs both build (the rider gains `path_provider` through
`zopiq_ui` without using it, which is the build worth checking). What no build can show
is the second cold start actually drawing from disk — that is a Phase 5 device check.

**What the 2026-08-09 sweep found: the gift bag was charged before it was priced**
*(migration 0112)*. `gift_checkout_page.dart` asked the gateway for `bag.subtotal` —
the bag's own arithmetic, which 0096 deliberately made **items only**, because tax is
the server's to add. `place_gift_order` then priced the same bag at `subtotal + GST`
and wrote *that* on the order. So the customer was charged the pre-tax figure, the
order recorded the tax-inclusive one, and the difference — 18% of every gift sold —
was booked as collected and never was. The screen was not even quietly wrong: the
button read **"Pay ₹500 + GST"** and then charged ₹500.

The food side has never had this because `bill.total` is tax-inclusive and the cart
mirrors `place_order` line for line (0082). Gifts had no mirror **on purpose**, and no
quote either — which left the client with nothing to pay but the subtotal. The fix is
not to teach the Dart cart the tax arithmetic: the rounding is once per slab and then
down to the lines of that slab by largest remainder, and two implementations of that
disagree the first time a bag holds an 18% mug and a 12% scarf — showing up as a
receipt that does not match the amount charged, which is the same bug in a smaller
size. So `gift_bag_quote` is the pricing block lifted *out* of `place_gift_order`, and
`place_gift_order` now calls it rather than keeping a second copy. **One
implementation, called twice**: once to show the customer what they are about to pay,
once to write it down. The checkout screen shows the real breakdown instead of a
sentence promising one, and the Pay button waits for the quote rather than guessing.

Two things fell out on the way. 0096's `_lines` temp table is gone — the arithmetic is
CTEs now, so the "second call in one transaction" trap its own comment warned about
stops existing, which matters precisely because a quote *is* a second call. And a
missing or null `quantity` used to fall through the range check (null is not `<= 0`)
and die three statements later on a not-null violation; it is checked before the join
now and gets the sentence it was always meant to get.

Verified in a rolled-back transaction against the live database, on a real two-slab
bag: quoted total == order total == `subtotal + fee + taxes`, `cgst + sgst == taxes`,
the per-line tax amounts sum to the order's, an idempotent retry returns the same
order and creates only one, `anon` cannot call the quote, and no overload was created.

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
