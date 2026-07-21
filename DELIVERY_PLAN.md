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

### 8b-3 — The customer sees their rider

Additive and small: name and phone on the tracking card while the order is out for
delivery. A read-only policy on `deliveries` for the order's own customer.

- **Verify:** customer tests green; an order with no rider renders exactly as it
  does today.

### 8b-4 — Hardening

- `/security-review` over every new policy and RPC.
- The edge matrix: order cancelled while a rider carries it; rider abandons a claim;
  two claims racing; a claimed order the kitchen then rejects; app killed mid-job.
- Auto-assign, if wanted, lands here or later — the schema already allows it.

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
- **No ops console still hurts.** Onboarding riders by seed file is fine for the
  first ten and untenable at a hundred. The admin dashboard is the honest next
  dependency after this phase.

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
