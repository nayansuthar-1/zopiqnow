# Zopiqnow — Delivery Plan (Phase 8b)

**Status date:** 2026-07-21
**Scope:** the delivery-partner domain — riders, dispatch, pickup handover, and a
rider-facing app. This is the executable build order for `VENDOR_TASKS.md` Phase 8b.

Phase 8a (staff roles) is done. This is the other half of Phase 8, and it is the
largest single piece of work left in the plan: net-new backend, a **third Flutter
app**, and the first change to the customer app's order surface since Phase 2.

---

## Decisions locked

- **Platform-wide fleet.** Riders belong to Zopiqnow, not to a restaurant. A rider
  can carry an order from any kitchen. *(User decision, 2026-07-21.)*
- **A rider app ships in this phase.** `apps/rider`, a fourth workspace member.
  *(User decision, 2026-07-21.)*
- **No new `orders.status` values.** See the hard constraint below.
- Architecture unchanged: feature-first Clean Architecture + Riverpod + go_router +
  Supabase, every write a `security definer` RPC. The rider app is built the same
  way the vendor app is, and reuses `zopiq_ui`.

## The hard constraint that shapes everything

`OrderStatus.fromWire` in the **customer** app *throws* on a status it does not
recognise:

```dart
_ => throw ArgumentError.value(value, 'status', 'Unknown order status'),
```

That was a deliberate choice (a receipt rendered from a contract we no longer
understand is worse than one that fails) and it is not being changed here. What it
means for this phase is concrete: **adding a value to `orders.status` breaks the
tracking screen on every customer build already installed**, and app updates roll
out over weeks. Phase 2 could do it because the customer app was made tolerant
*first*, in a release that shipped ahead of the migration. We are not paying that
cost again for something we do not need.

So: the existing statuses already describe delivery.

```
placed → accepted → preparing → ready_for_pickup → out_for_delivery → delivered
                                       ↑                   ↑              ↑
                              rider can claim it    rider picked up   rider dropped
```

The rider's *own* lifecycle — offered, assigned, picked up, dropped — lives in a
new `deliveries.state` column that the customer app never reads. `orders.status`
is written by the same two transitions it already has. Old customer builds see a
perfectly ordinary order.

## The dispatch problem, stated honestly

A platform fleet implies a dispatcher, and **there is no ops console** to be one
(`PM_CHECKLIST` §8: the admin dashboard does not exist). Two ways out:

1. **Riders self-claim** from a board of unclaimed ready orders. No dispatcher
   needed, and the race between two riders tapping the same order at the same
   second is solved in one `select … for update`.
2. **Auto-assign** by proximity or round-robin. Needs rider location, a retry when
   nobody accepts, and a human to intervene when the retry also fails — i.e. it
   needs the console we do not have.

**This phase builds (1).** Auto-assign is a later slice that can be added on top
without changing the tables, because "who claimed it" and "who was assigned it"
are the same column either way.

Rider onboarding has the same shape of answer: until an admin dashboard exists,
"ops" is a seed file — exactly as `restaurant_staff` worked before 0024.

## The handover, and which way the OTP points

The vendor shows a 4-digit code on the ticket; **the rider types it into the rider
app**. Not the other way round. The code proves the rider is physically standing at
that counter — a rider who can type it has been handed the bag. A code the *rider*
shows and the *vendor* types would prove only that the rider can read their own
screen, which is not a fact anyone needs.

The vendor's existing "Hand to rider" button stays and keeps working. A restaurant
with no rider claimed on the order must still be able to hand a bag to a cousin
with a scooter, and that path is unchanged.

---

## Slices

Each leaves every app building and shippable.

### 8b-1 — The domain, and the vendor's half  ✅ **DONE** *(migration `0025`)*

Backend, plus the vendor changes that make it visible. No customer-app change, no
rider app yet — this slice is the foundation both later slices read.

- [x] `delivery_partners` — keyed by **email**, for the reason `restaurant_staff`
      is (0009): ops grants access to an address before that person has ever
      opened the app and been issued a uid. Platform-scoped: no `restaurant_id`.
- [x] `deliveries` — one row per order a rider is carrying. `state` in
      `claimed/picked_up/delivered/cancelled` — **no `offered`**, as planned: with
      riders claiming for themselves, an unclaimed job is simply an order with no
      row here, so the board is a `not exists`, not a state.
- [x] A **partial** unique index (`where state <> 'cancelled'`) rather than a plain
      `unique (order_id)`. A rider who drops a job leaves a cancelled row behind
      and the order returns to the board; a plain unique would have made that
      abandonment permanent and "who dropped this, and when" unanswerable.
- [x] `delivery_partner_email()` — the rider's twin of `staff_restaurant_id()`,
      null for a *deactivated* partner, so ops flipping `is_active` takes someone
      off the board without any function needing to know that is why.
- [x] **`orders` gained no new policy at all.** Every rider read goes through a
      `security definer` function instead. This was the plan's biggest risk and it
      turned out to be avoidable: that table's policies encode "customers see
      their own, staff see their restaurant's", and a third clause bolted on is a
      third way for the first two to be widened by a later edit. A function
      returning ten named columns cannot leak an eleventh.
- [x] Vendor: rider name and state on the ticket, and the pickup code — shown
      *only* while the food is packed and the rider has not yet typed it.
- [x] **Verified** via psql in rolled-back transactions: the claim race (one
      winner, the loser told plainly), abandon → back on the board → re-claim,
      the full OTP handover, a rider's inability to see a job they do not hold,
      the board refusing a non-rider, and the vendor's own hand-off untouched.
      Vendor 62/62 green, analyze clean.

> **Bug caught by that verification, worth remembering:** `confirm_pickup`
> originally updated `where order_id = …` without scoping to the live row. On an
> order that had been claimed, dropped and re-claimed, that dragged the cancelled
> row to `picked_up` too and hit the partial unique index. The reclaim path is the
> only way to see it, which is exactly why it was worth walking.

### 8b-2 — `apps/rider`  ✅ **DONE**

A fourth workspace member. **No new dependencies** — it takes only versions the
root lockfile already froze (`flutter_riverpod`, `go_router`, `supabase_flutter`,
`flutter_secure_storage`, `zopiq_ui`). The version freeze holds.

- [x] Auth: email OTP, the vendor app's flow almost exactly — including its
      "authenticated but not a partner" fourth state, which is the same problem
      here. Session in the Keystore under its **own** key: one person can be a
      customer *and* a rider on the same phone, and a shared key would mean
      signing into one signs you out of the other.
- [x] The board, and the job in hand — as *one* screen with two moods, not two
      tabs. A rider carrying a bag has exactly one thing to do, and a board of
      other people's jobs underneath it is an invitation to do the wrong one.
- [x] Claim → (drop) → enter the restaurant's code → delivered.
- [x] Tests mirror the vendor harness: fakes for every data source, no Supabase.
      **12/12 green**, analyze clean, **debug and release APKs both build.**
- [x] First rider seeded (`seed/0006`): `nayan@siteonlab.com`.

> **Two things worth carrying forward.** The `is_active` filter in
> `_resolveRider` is load-bearing: `delivery_partner_email()` returns null for a
> deactivated partner but the *select policy* has no such clause, so without it a
> deactivated rider gets all the way in and is then refused by every single
> action. And a fresh `flutter create` does **not** carry this repo's
> `kotlin.incremental=false` workaround, without which the Android build fails
> outright on Windows — the other two apps both document it.

### 8b-3 — The customer sees their rider  ✅ **DONE** *(migration `0039`)*

Name, vehicle and phone on the tracking card while the order is out for delivery.
Two select policies and nothing else — no table, no function, no status, and
`orders` untouched for the third slice running.

Both policies are scoped to `state = 'picked_up'`, which is narrower than the
kitchen's window. Not `claimed`: a rider who has taken the job but not reached the
counter may still drop it, and a name that appears and then changes is worse than
one that arrives a few minutes late. Not `delivered`: the job is over and the
rider's personal number is theirs again. *(User decision, 2026-07-22.)*

The app asks once, on a `FutureProvider`, when the live status says
`out_for_delivery` — not a stream. Realtime rides the same policy, so a
subscription opened any earlier would be a socket held open for a row it is not
yet allowed to see.

- **Verified:** all four cases exercised through the policies in a rolled-back
  transaction — invisible while `claimed`, both rows visible to the order's owner
  while `picked_up`, invisible to a *different* signed-in customer in that same
  window, invisible again once `delivered`. Customer tracking tests 9/9.

### 8b-4 — Hardening  ✅ **DONE** *(migration `0041`)*

Every policy and RPC from 0025, 0039 and 0040 read line by line, and the edge
matrix run against the live database in a rolled-back transaction. **Ten
scenarios, one failure**, plus two findings left deliberately unfixed.

**Fixed in 0041:**

1. **`confirm_delivered` never looked at the order.** It checked that the caller
   held a `picked_up` row and then wrote `delivered` over whatever the order
   said — its twin `confirm_pickup` has always checked. Not reachable today
   (nothing moves an order out of `out_for_delivery` except this function: 0014
   gives the kitchen no transition out of it, and the 0008 demo cron is
   unscheduled — confirmed against `cron.job`, only the settlement batch runs).
   The matrix had to fabricate the state to prove it. Closed anyway, because the
   day customer-side cancellation lands it becomes a cancelled order that reports
   itself delivered, settles, and is charged for.
2. **The customer's phone outlived the delivery.** `my_deliveries` handed back
   `user_phone` for every job a rider had ever held, so a rider a year in had a
   contact list of everyone whose dinner they had carried. Now null once
   `delivered` — the mirror of 0039's rule in the other direction. The address
   stays: it is how a rider recognises a past job, and it is not a way to reach
   anyone. No app change, because the rider app renders only the live job.
   *(User decision, 2026-07-22.)*

**Reviewed and left alone, with reasons:**

- **No cap on concurrent claims.** Carrying three orders from one street is how
  delivery works. The abuse case is answered by riders being hand-onboarded and
  switchable off, not by a number in a function.
- **`available_deliveries` shows the full delivery address before claiming.**
  Narrowing it to an area is a real improvement and a bigger change than this:
  the board is how a rider decides whether a job is worth taking, and "somewhere
  in Banjara Hills" is a different decision from an address. **Still open.**
- **A rider deactivated *while carrying* still strands the order.** 0040 refuses
  it through the console, the only route ops has; direct SQL bypasses that as it
  bypasses everything. Making it structural needs an admin force-abandon, which
  is a support flow that does not exist yet — inventing its shape here would be
  guessing. **Still open.**

**Verified green:** two riders racing (one wins, the loser is told plainly) ·
abandon returns the job to the board and another rider takes it · the kitchen
cancelling a claimed order leaves the rider able to drop it and unable to pick it
up · wrong pickup code refused twice, right one hands over and moves the order to
`out_for_delivery` · a picked-up job cannot be dropped · a rider who is not
carrying it cannot deliver it · delivering twice refused · the app being killed
loses nothing, the job is in Postgres.

Auto-assign and job-offer push remain unbuilt and unneeded — the schema still
allows both without a migration.

---

## Risks

- ~~**`orders` gains a third kind of reader.**~~ **Retired in 8b-1** — no policy was
  added to `orders`; riders read through `security definer` functions only. The
  security review in 8b-4 still stands, but this particular hazard no longer exists.
- **A rider app is a real app.** Auth, session storage, release signing, a store
  listing eventually. 8b-2 is scoped to "builds and runs", not "shipped to a store".
- ~~**Nobody can sign in as a rider yet.**~~ **Resolved in 8b-2** —
  `nayan@siteonlab.com` seeded as the first partner. Onboarding is still a seed
  file, and still stops scaling around the tenth rider; the admin dashboard is
  the honest next dependency after this phase.
- **The board does not refresh itself.** `available_deliveries` is a function, and
  Realtime rides table policies, not functions — and riders have no policy on
  `orders` by design. So a new job appears on pull-to-refresh and not before. A
  job-offer push is the fix and belongs in 8b-4.
- ~~**No ops console still hurts.**~~ **Retired 2026-07-22** — the admin console
  now has a Riders page (migration `0040`: `admin_list_riders`, `admin_add_rider`,
  `admin_update_rider`, `admin_set_rider_active`). Riders are onboarded by an
  admin, and the seed file is history rather than the mechanism. Dispatch is still
  self-claim; nothing about the rider app changed.

## Progress log

- **2026-07-21** — Plan written. Fleet model and rider-app scope decided by the
  user; no-new-statuses and self-claim dispatch derived from the constraints above.
- **2026-07-21** — **8b-1 landed.** Migration `0025`: `delivery_partners`,
  `deliveries`, `delivery_partner_email()`, and six rider RPCs
  (`available_deliveries`, `claim_delivery`, `abandon_delivery`, `my_deliveries`,
  `confirm_pickup`, `confirm_delivered`). Vendor app gained `features/delivery`
  and the rider strip on the order ticket. `orders.status` untouched — not one new
  value — so every customer build in the wild is unaffected. Vendor 62/62 green.
- **2026-07-21** — **8b-2 landed.** `apps/rider`, the fourth workspace member, with
  no new dependencies. Email-OTP auth (four states, own Keystore key), the board,
  claim/drop, the pickup-code handover and delivery. 12/12 green, analyze clean,
  debug + release APKs build. First partner seeded (`seed/0006`).
- **2026-07-22** — **8b-3 landed.** Migration `0039` (the admin console filled
  0026–0038 in between): two select policies giving the order's own customer the
  rider's name, vehicle and phone, and only while `picked_up`. `OrderRider` +
  `getRider` through the existing repository; a strip on the tracking card that
  renders nothing at all when nobody is carrying the order. Policies verified
  against a rolled-back transaction including both negatives. Customer suite
  122 pass / 11 fail — every one of those 11 pre-dates this slice (see below).
- **2026-07-22** — **Riders moved into the admin console.** Migration `0040`: four
  admin RPCs behind `assert_admin()`, a Riders page beside Restaurants, and one
  refusal worth the whole slice — a rider carrying an order cannot be deactivated,
  because `delivery_partner_email()` going null mid-job would strand that order
  where no rider could claim it and no screen could finish it. Verified in a
  rolled-back transaction including the non-admin and mid-delivery cases.
- **2026-07-22** — **8b-4 landed, and Phase 8b is closed.** Migration `0041`:
  `confirm_delivered` now checks the order's status, and `my_deliveries` stops
  returning the customer's phone number once the job is done. Ten-scenario edge
  matrix run against the live database, all green after the fix. Rider 12/12,
  analyze clean. Two findings left open on purpose (board addresses, admin
  force-abandon) — both written up above rather than half-built.
- **2026-07-22** — **Main was already red.** `flutter test apps/customer` fails 11
  tests on a clean checkout of `main`, in `app_shell`, `order_history`,
  `address_test` and others. One of them — `OrderStatus.journey` asserting five
  stages when Phase 2 made it six — was fixed here because it sits in the file
  8b-3 touched. **The other 11 are untriaged and owed.** Run the suite early;
  HEAD is not green.

## Phase 8c — a delivery is worth something

Phase 8b closed with a rider who could do the job and no number anywhere saying
what the job was worth. This is that number, and the screen that shows it.

**The model (user decision, 2026-07-22):** a base fee plus a per-kilometre rate,
chosen over a flat fee and over a percentage of the order value — that last one
pays less for a ₹150 order than a ₹1500 one when the ride is identical.

**The precondition nobody had noticed.** All eight restaurants on the platform
had `latitude = null`. 0027 left the columns nullable (correctly — the seeds had
none) and the console has always offered them as optional, so a distance-based
fee would have paid the base and nothing more, forever, while looking in every
screen exactly like it was working. Migration `0042` makes a map location
required to publish. The eight already-live rows are untouched; the check runs
when somebody publishes, which does mean a restaurant delisted and brought back
needs its coordinates first.

**The distance is haversine and therefore wrong, in a known direction.** It is
the straight line, never the road, so it is always at or below what was actually
ridden — it underpays and cannot overpay. Two consequences, both deliberate:
`distance_km` is stored on the delivery rather than folded into a total, so a
rider disputing their pay can be shown what was measured; and the rates are
admin-editable, so the answer to a badly-shaped city is to raise the base. A road
distance needs a routing API called inside a claim, and that is its own slice.

**Named `rider_pay`, never `delivery_fee`.** `orders.delivery_fee` has existed
since 0003 and is what the *customer is charged*. The two describe the same ride
and are not the same money.

- **`0042`** — `admin_publish_restaurant` requires latitude and longitude.
- **`0043`** — `rider_pay_rates` (one row, platform-wide, enforced by the primary
  key); `delivery_distance_km()` (haversine, null-in-null-out); four snapshot
  columns on `deliveries`; `claim_delivery` takes the snapshot; `my_deliveries`
  rebuilt to carry it; `rider_earnings(from, to)`; and the two admin RPCs.
- **Rider app** — a three-tab shell (Jobs · Earnings · Profile), an Earnings
  screen showing today and the last seven days with every job's arithmetic spelled
  out, and a Profile screen that finally gives sign-out a label instead of an
  unmarked icon in the corner of the busiest screen.
- **Admin console** — a Rider pay card on Settings, beside the admin roster.

Verified in rolled-back transactions against the live database: haversine returns
111.19 km for one degree of latitude and 0.00 for a point against itself without
an `asin` domain error; a claim snapshots all four columns and the total equals
its parts; a missing coordinate pays base only and records null rather than zero;
a rate change does not reprice a claimed job while abandon-then-reclaim correctly
takes the new one; earnings count `delivered` only, never `claimed`, `picked_up`
or a dropped job; the rate bounds refuse 50000 and -1; and the publish gate fires
on a null pair and on half a pair. Rider 17/17, analyze clean, release APK builds.

**Still owed, and it is a blocker for the per-km half:** the eight seeded
restaurants need real coordinates typed into the console. Until then every job
from them pays the base fee and says so on the rider's screen, in those words.

### Open, on purpose

- **Nothing pays the rider.** This records what is owed; there is no rider payout
  batch the way `run_settlement_batch` (0017) exists for restaurants. Deliberate —
  a payout run needs a bank account per rider, which the roster does not collect.
- **No cap on concurrent claims** (carried over from 8b-4), and pay now gives that
  a sharper edge: claiming five jobs snapshots five fees.
- **The board still cannot refresh itself.** Unchanged since 8b-2.
