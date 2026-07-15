# Zopiqnow — Development Plan

**Status date:** 2026-07-10
**Scope of this document:** the *executable* build order for the customer app.

This is not a restatement of [`ZOPIQNOW_ARCHITECTURE.md`](ZOPIQNOW_ARCHITECTURE.md) Section 25/26.
That roadmap assumes parallel squads (Platform, Backend, Mobile×3, Admin, QA) and a
backend landing in step with the app. We do not have that. What we have is one
Flutter customer app on mock data and no backend.

So this plan is **frontend-first against mock data sources**, ordered so that every
step ends in something you can open on a phone and judge. The repository seam that
makes this safe already exists: every feature reads a `Repository` interface, and the
mock data source behind it is swapped for HTTP without any UI change (SAD 7.4).

---

## Guiding rules

1. **One vertical slice at a time.** Domain → data → providers → UI → test → run it on
   a device. A slice is not done until it renders on hardware.
2. **Mock, then wire.** Never block UI work on the backend. Never build a UI against a
   contract that doesn't exist yet.
3. **No half-slices on `main`.** If a feature has entities and providers but no screen,
   it is not shippable and should not be merged.
4. **Version freeze holds.** No dependency, SDK, or tool version changes outside an
   explicit, approved upgrade task.
5. **Android 10 is the floor.** Every slice gets scrolled on a real device before merge.

---

## Where we actually are

### Done and merged
- **Monorepo + `zopiq_ui` design system** — tokens (color, spacing, radii, elevation,
  motion), light/dark theme, `ZopiqCard`, `ZopiqButton`, `ZopiqShimmer`,
  `ZopiqVegIndicator`. Single source of truth; no feature hardcodes a hex value.
- **Home — restaurant discovery** — repository + mock data source, `AsyncValue` feed
  with shimmer / data / empty / error states, pull-to-refresh.

### Done, this step (uncommitted)
- **Brand typeface.** Figtree (SIL OFL) bundled in `zopiq_ui`, wired through one
  constant in `ZopiqTypography.fontFamily`. Variable font; weights come from
  `FontVariation` so nothing is fake-bolded.
- **Home rebuilt to the Swiggy layout.** Snapping location/search header, offers
  carousel, "What's on your mind?" category rail, section dividers, "Top restaurant
  chains" rail, pinned filter-chip row, filterable restaurant list.
- **Working filters.** Fast Delivery / Rating 4.0+ / Pure Veg / Great Offers toggles
  plus a sort sheet, with a dedicated "no matches" empty state.
- **`ZopiqPressable`** — the scale-on-press micro-interaction used by every image-led
  tile. Animates a `Transform` only, so a press repaints nothing.

### Done — menu + cart slice (Step 1)
Menu screen (collapsing Hero header, vitals, Veg-only switch, categorised dish tiles),
cart screen (line steppers, bill breakdown, free-delivery nudge), routes
`/restaurant/:id` and `/cart`, the sticky `CartBar`, and the "start a new cart?" prompt
when adding across restaurants. `getRestaurantById` was added to the repository so a
cold deep link resolves without the Home feed.

### Known gaps, deliberately accepted for now
| Gap | Why it's acceptable today | When it must be fixed |
|---|---|---|
| Category art is OpenMoji, not commissioned illustration | Free and properly licensed (CC BY-SA 4.0). Swiggy's own illustrations are copyrighted and are not an option | Whenever brand art is ready |
| ~~No licenses/credits screen~~ | ✅ Shipped. Reachable from Home's profile button | done |
| Restaurant images are deterministic gradients | No CDN, no image pipeline | Step 3 |
| ~~Location picker is a dead tap~~ | ✅ Shipped. GPS + saved addresses, persisted | done |
| ~~Favourites is a dead tap~~ | ✅ Shipped (migration 0007). The heart on the restaurant card replaced a *decorative bookmark glyph* — an icon that looked tappable, was not, and did nothing | done |
| ~~Recent searches vanish on restart~~ | ✅ Shipped. Persisted through `KeyValueStore` — local, not account state, for the same reason the selected address is | done |
| ~~No auth, no real location~~ | ✅ Shipped in Step 5 (this table previously said "Steps 6 and 7", contradicting the build order) | done |
| ~~"Proceed to checkout" only explains itself~~ | ✅ Now opens the auth-guarded `/checkout` | done |
| OTP accepts a fixed code | No backend and no SMS provider. The mock enforces the real rules (TTL, attempt cap) so the UI is built against the true contract | Step 7 |
| Access tokens are never refreshed | Nothing calls an authenticated endpoint yet | Step 7, with the Dio interceptor |
| `kotlin.incremental=false` | Gradle 9.1.0 + Kotlin 2.3.20 cannot release their incremental caches on Windows; the build fails outright without it. Costs full Kotlin recompiles | Next Gradle/Kotlin upgrade |
| Delivery fee and tax are hardcoded | Real fees depend on distance/surge; real tax on HSN category. Isolated in `CartBill` | Step 7, with the pricing engine |
| Payments are COD-only | `razorpay_flutter 1.4.5` is approved and pinned, but checkout needs a key id and a server-created payment order | Step 7 |
| Coupon codes are advertised on the checkout screen itself | The mock coupon book has no campaign behind it; the hint is the campaign | With the promotions service |
| ~~A cron job advances order status, not a kitchen~~ | ✅ Gone (migration 0009). A real vendor moves the order now; the simulator lasted one day, exactly as intended | done |
| Restaurant accounts are seeded by SQL | There is no admin dashboard, so "ops" is a seed file. Self-service signup would let anyone claim a kitchen | With the admin dashboard (PM §8) |
| No driver location, no tracking map | Needs a Maps billing account + key (PM §5) *and* a rider app emitting a location. Neither exists | Step 8's remainder |

---

## Build order

### ~~Step 1 — Finish the menu + cart slice~~ ✅ done
Verified on device: tap a card → menu → ADD → cart bar → correct total.

### ~~Step 2 — Bottom navigation shell~~ ✅ done
`StatefulShellRoute.indexedStack` with Home and Cart branches, a live cart badge, and
a credits screen behind the profile button. Search and Account tabs arrive with their
features — each is one more `StatefulShellBranch`. Verified: Home scroll position
survives a tab switch.

### ~~Step 3 — Image pipeline~~ ✅ done
`ZopiqNetworkImage` handles loading (shimmer) / loaded (fade-in) / failed (branded
gradient) once, so no call site reinvents them. Bitmaps decode at draw size via
`cacheWidth`. Restaurant and dish photos are live; mock URLs point at foodish-api.
`INTERNET` added to the release manifest — Flutter only declares it for debug, so
release builds were silently going to fail every image.

**Still owed here:** caching is Flutter's in-memory `ImageCache` only. Images survive
a scroll, not an app restart. Disk caching needs `cached_network_image`, a new
dependency and therefore an explicit, approved decision.

### ~~Step 4 — Search~~ ✅ done
Debounced query (300ms) against the repository, matching restaurant names and
cuisines. Recent searches, recorded on submit or on opening a result — never from
the debounced provider, which would log every prefix the user paused on. Results
reuse `RestaurantCard`. Home's search bar and the Search tab are both live.

Search matches **names and cuisines, not dish names**: every mock restaurant returns
the same menu, so a dish index would return nonsense. The hint text says so. A real
dish index arrives with the search service.

### ~~Step 5 — Auth + location~~ ✅ done
Phone-OTP flow against a mock `AuthRepository`, the session in Keystore-backed secure
storage, `go_router` redirect guards, and a real address picker. The hardcoded
`Banjara Hills, Hyderabad` is gone: Home reads `selectedAddressProvider` and shows
"Set delivery location" when nothing is chosen, rather than inventing a city.

**Approved dependency additions (Rule 3 change request).** The first four since
kickoff, pinned exactly. `pubspec.lock` gained 61 packages and bumped none:
`flutter_secure_storage 10.3.1`, `shared_preferences 2.5.5`, `geolocator 14.0.3`,
`geocoding 5.0.0`. Verified `minSdk 24` survives the manifest merge —
`flutter_secure_storage` declares 23, and nothing raised our floor.

Decisions worth remembering:
- **Only `/checkout` is guarded.** Browsing, searching, and building a cart need no
  account — that is how a food app works, and demanding a phone number before the
  user has seen a menu is how you lose them. Identity is required where money and an
  address are. `_protectedPrefixes` in `router.dart` is the one place to extend.
- **The redirect owns navigation after sign-in.** The OTP screen never pops itself;
  `?from=` carries the intended route through login, so a cold deep link to a guarded
  route survives the session restore instead of dumping the user on Home.
- **`AuthUnknown` is a real state, not a spinner.** It is the window between launch
  and the Keystore read returning. The splash renders it; redirecting during it would
  bounce a signed-in user to the login screen on every cold start. A Keystore read
  that *throws* degrades to signed-out rather than stranding them there (Rule 1.6).
- **Reverse-geocoding uses Android's native `Geocoder`** (`geocoding`), not the Google
  Geocoding API — no key, no billing. Guarded by `isPresent()`, because a device with
  no Play services has no geocoder (Rule 1.1).
- **Foreground location only.** `ACCESS_BACKGROUND_LOCATION` is deliberately not
  declared: we resolve an address while the picker is open and never track.

**Still owed here:** the OTP is verified by `AuthMockDataSource` (fixed code `123456`,
shown on-screen in debug builds only, since there is no SMS to read). It models the
real contract — 6 digits, 5-minute TTL, 5-attempt cap — so Step 7 swaps the transport
without discovering new failure modes. ~~Saved addresses are seeded rather than
per-user; there is no add/edit-address screen~~ — both fixed in Step 7 (migration 0006).
There is still no Places autocomplete: the form forward-geocodes typed text through
Android's native `Geocoder`, which needs no key and no billing. Access-token
refresh-on-401 arrives with the Dio interceptor, as nothing calls an authenticated
endpoint yet.

`/checkout` is a **stub**: it confirms *who* is ordering and *where* it goes — the two
things this step exists to establish — and says plainly that payment arrives next. It
is the guard's destination, not Step 6's screen.

### ~~Step 5.5 — Home first-impression revamp~~ ✅ done
Brand-colored app bar with a white search pill and a full-bleed animated campaign
banner (rotating ray bursts, pulsing CTA — transforms only). The placeholder
composition is isolated in one widget for a one-asset swap when brand art arrives.
Ambient loops respect OS reduce-motion, which is also what keeps `pumpAndSettle`
settling in tests.

### Step 6 — Checkout + payments ← **in progress; COD slice built, device check pending**
Shipped frontend-first against a mock `OrderRepository`, same as every other slice:
order recap, coupon apply/remove (validated service-side by the mock: minimum order
value, capped percentages — the client never computes a discount), bill with
discount, payment-method selection, order placement, and an order-confirmation
screen. Placing an order clears the cart; the receipt lives in
`lastPlacedOrderProvider`, not route `extra`.

Decisions worth remembering:
- **COD is the only live payment method.** Razorpay is a new dependency — the
  version freeze (Rule 4) requires an explicit approved change request — and online
  payment needs a backend to create the payment order anyway. The UPI tile is
  honestly disabled ("arrives with online payments") rather than dead.
- **A coupon is invalidated by any cart change.** `CheckoutController` resets when
  the cart's subtotal changes: the validation ran against the old subtotal, and
  honouring a discount the order service never approved is how money is lost.
- **`CartBill` gained a `discount` field but never computes one** — it subtracts
  what the (mock) service approved. Coupon rules stay server-side.

**Still owed here:** the Razorpay checkout wiring. The dependency change request
was **approved 2026-07-10** and `razorpay_flutter 1.4.5` is pinned in the app
(minSdk 19 — under our floor), but opening the gateway needs a Razorpay key id
and a server-created payment order, so the UPI tile stays disabled until the
backend (Step 7). The `PaymentMethod` seam is already in place. Verify on the
Android 10 device before calling the step done.

### Step 7 — Backend wiring ← **in progress**
Swap each mock data source for its HTTP implementation, one repository at a time. If
the domain layer was respected, no widget changes. This step is the test of whether it
was. Absorbs Razorpay (UPI/cards): the SDK is a dependency change request, and online
payment needs the backend to create the payment order.

Catalog, menus, pricing and coupons, and order placement are on Postgres. Auth is the
last mock, and it moved to **email OTP, not SMS** — there is no SMS provider yet
(2026-07-13). Decisions worth remembering:
- **Email is the identity; the phone number is a delivery detail.** An account can
  exist without a number, so checkout asks for one before it will place an order and
  stores it in the user's metadata. Supabase's `phone` column is deliberately not used:
  writing it starts an SMS verification we cannot complete.
- **The session lives in the Keystore, not SharedPreferences.** `supabase_flutter`
  defaults to prefs — a plaintext file holding a long-lived refresh token — so
  `SupabaseSecureLocalStorage` points it at the same secure store we always used.
- **`place_order` no longer takes a user id** (migration 0004). It reads `auth.uid()`
  from the caller's JWT. A client that can name the buyer can buy in someone else's name.
- The phone-OTP mock is gone rather than parked: it was typed against a domain that no
  longer exists, and the rules it modelled (6 digits, TTL, attempt cap) are now enforced
  by Supabase. Git history has it; `FakeAuthDataSource` carries the same rules in tests.

**Email OTP is live (2026-07-14).** The sender is Brevo (`smtp-relay.brevo.com`), not
Gmail: Google answers `534 5.7.9 WebLoginRequired` to a login from Supabase's datacenter
IPs even with a valid App Password, and the `DisplayUnlockCaptcha` page that used to
whitelist such logins no longer exists. Gmail is a mailbox, not a relay — do not retry it.
Brevo's free tier sends 300/day to any recipient with no domain to verify, which is what
buys us time; move to Resend on a real domain before launch. The mail template lives in
`supabase/templates/otp_email.html` and is applied to *both* the confirmation and
magic-link templates, because Supabase picks between them on whether the account already
exists and the user must not be able to tell which one they got.

**Google sign-in is live (2026-07-14).** Native, not the browser OAuth flow: the account
sheet returns an id token that goes straight to `signInWithIdToken`, so the user never
leaves the app and there is no redirect scheme to register. `google_sign_in 7.2.0` was an
approved Rule 3 change request; `pubspec.lock` gained 6 packages and bumped none, and the
merged manifest still reads `minSdk 24`.

Decisions worth remembering:
- **The app is configured with the *Web* client id, not the Android one.** Native sign-in
  asks for a token addressed to a backend, and the backend is Supabase, which holds that
  same web client. The Android client must exist — it is what ties the signing certificate
  to the app — but it is never named in code. The release SHA-1 is still owed for Play.
- **A dismissed account sheet is not an error.** `GoogleSignInCancelled` is swallowed by
  the email screen; only real failures get a message.

**Order history is live (2026-07-14).** `/orders` and `/orders/:id`, reached from the
Account tab: past orders newest-first, the bill as it was actually charged, and reorder.
Both routes sit behind the auth guard — a receipt carries the phone number the rider
called and the address the food went to, so an order history *is* identity.

Decisions worth remembering:
- **The read is an RLS policy, not another `security definer` function** (migration 0005).
  0003 left the order tables invisible to the client and said the functions were "the only
  way in" — but the reason money moves through `place_order` is that *the client must not
  decide what anything costs*, an argument about pricing, not about visibility. It says
  nothing about a customer reading a receipt they already paid for. So `select` is scoped
  to `auth.uid()`, and PostgREST returns the order, its items, and the restaurant's photo
  in one round trip. Nothing grants insert/update/delete: an order is immutable to the
  customer once placed.
- **The restaurant's name is now stored on the order** (also 0005, with `place_order`
  updated to write it). It was only ever a `restaurant_id`, and the catalog policy is
  `using (is_active)` — so the day a vendor is delisted, every past order of theirs would
  have rendered with a blank name. `order_items` already denormalizes dish names for this
  exact reason. The photo is *not* copied: it is decoration, and the UI falls back.
- **Reorder re-prices against today's menu.** The order's lines are resolved by id and the
  cart is rebuilt from the current `MenuItem`s, never from the receipt's prices — a cart
  restored from a three-month-old order would otherwise promise last quarter's prices, and
  `place_order` would reprice it at checkout anyway. Items that are gone are skipped and
  counted, and an order where *nothing* survives leaves the existing cart untouched rather
  than emptying it for nothing.

**The address book is live (2026-07-14).** `/addresses`, reached from the Account tab:
the account's saved addresses in Postgres (migration 0006), an add/edit form, and delete.
Guarded, like `/orders` — there is no such thing as a signed-out user's saved addresses.
The seeded `Home — Banjara Hills` / `Work — HITEC City` constants are gone from the app;
they were shared by *every account* and now live in `AddressMockDataSource`, where fixtures
belong.

Decisions worth remembering:
- **The list is the account's; the selection is the device's.** Which address this phone is
  ordering to is not a fact about the account — the same customer can be at home on one
  phone and at the office on another — so it stays in local storage, and the Home header
  still renders on the first frame with no network call. `AddressRepositoryImpl` holds both
  seams because they must be kept in step: editing the selected address rewrites the local
  snapshot, and deleting it clears it, or the header goes on showing an address the next
  order would ship to.
- **The client may write this table**, unlike `orders`. That is the distinction worth being
  precise about: `place_order` owns writes because *the client must not decide what anything
  costs*. An address costs nothing — it is the customer's own text about where they live —
  so the only rule is "it is yours", and RLS enforces exactly that (insert carries a
  `with check`, update carries both clauses, so no row can be filed under another user).
- **Coordinates come from GPS, then from a forward geocode, then not at all.** The table
  requires a lat/lng — an address the dispatcher cannot put on a map is not a delivery
  address — but customers type words, not points. A point already attached to unchanged text
  is reused (re-geocoding "Flat 402, Banjara Hills" would throw away a real GPS fix for a
  neighbourhood centroid); changed text is forward-geocoded through the native `Geocoder`,
  which is what lets someone save their *office* address from their sofa; and if neither
  yields a point, the form refuses to save and says why. `geocoding` already ships — no new
  dependency.
- Deleting an address cannot damage history: an order stores `delivery_to`/`lat`/`lng` on
  itself (0003), so a receipt still says where the food went.

**Still owed here:** the Razorpay wiring inherited from Step 6, and Google sign-in has not
yet been exercised on the Android 10 device — it builds and the unit tests pass, but a
plugin that talks to Play services is only really tested on hardware. Order history has
been verified against Postgres (the policy isolates by uid) and in widget tests, but it has
only been installed on the Android 13 device, not the Android 10 floor.

### Step 8 — Order tracking ← **in progress; live status shipped, map blocked**
`/orders/:id` is now the tracking screen: while an order is open it carries a live
timeline (Placed → Accepted → Preparing → Out for delivery → Delivered) and the arrival
time it was promised, instead of a static status chip. "Track this order" on the
confirmation screen finally does what it says — it opens the order, not the list.
Realtime over `supabase_flutter`'s `.stream()`, so **no new dependency**.

Decisions worth remembering:
- **The subscription is the select policy, staying open.** 0005 already said a customer
  may read their own order; 0008 adds `orders` to the `supabase_realtime` publication,
  and Realtime applies that same RLS per subscriber. Publishing the table decides what
  is *available* to be filtered — not who sees it. `order_items` is deliberately not
  published: lines never change after `place_order` writes them, and a subscription to a
  table that cannot change is a socket that will never speak.
- **A cron job plays the kitchen, and is written to be deleted** (0008). Nothing moved an
  order past `placed` — in production the vendor app does, and we don't have one. So
  `advance_open_orders()` walks open orders through the same six statuses on a schedule
  derived from the ETA *the customer was actually quoted*: deliver in four minutes flat
  and the screen contradicts the "arriving in about 30 min" the confirmation promised.
  It touches only `status`, has no grant and no API surface, and the app cannot tell a
  status it wrote from one a kitchen wrote. When the vendor app lands:
  `select cron.unschedule('advance-open-orders')`, drop the function, change zero Flutter.
- **The mock does not simulate the kitchen.** `OrderMockDataSource.watchOrderStatus`
  emits the current status once and stops. A fake that marched an order to `delivered` on
  a timer would be testing its own timer; the timeline is tested by pushing statuses at
  the widget instead.
- **`orderByIdProvider` fetches now, rather than reading the loaded history.** It was a
  lookup into the list, on the reasoning that the detail screen is only opened *from* the
  list. "Track this order" ended that: checkout loads nobody's history, so the lookup
  would have missed and told the customer their brand-new order does not exist. A cold
  deep link to `/orders/ZPQ-1042` works now for the same reason.
- **Words that asserted a delivery that hasn't happened are gone.** The screen renders
  before the food arrives now, so "Delivered to" is "Delivering to" while the order is
  open, and a cash order nobody has paid for says "Total", not "Total paid".

**Still owed here:** the driver location stream and the tri-tracking map — blocked, and
not on us: they need the Google Maps (or Ola/Mappls) billing account and key from
PM_CHECKLIST §5, and a rider app that emits a location. Nothing to build until both
exist. The Postgres half is verified against the live database (cron fires, status
advances); the **Realtime → Flutter leg has not been exercised on a device**, and a
socket is only really tested on hardware.

### Step 10 — The restaurant app — **new scope, 2026-07-15; order queue shipped**
`apps/vendor` — a second Flutter app in the same workspace, on the same design
system, against the same Postgres. **No new dependency:** every package it uses is
one the customer app already pins, and `pubspec.lock` did not move.

Shipped: sign-in, the live order queue, and the four moves that carry an order —
Accept → Start preparing → Hand to rider → Mark delivered, plus Cancel while the
food is still in the building. One screen, oldest ticket first, each ticket carrying
what to cook, who to call, and what to collect.

Decisions worth remembering:
- **The cron simulator is gone** (migration 0009 unschedules it and drops the
  function). It existed for one day, because nothing else moved an order past
  `placed`. Something does now. Leaving it running would have meant a vendor and a
  cron job both writing `status` — a kitchen pressing "Accept" on an order the
  simulator had already sent out for delivery.
- **Staff are keyed by *email*, not by `auth.uid()`.** Ops onboards a restaurant days
  before anyone at that kitchen has ever opened the app and been issued a uid. A table
  keyed by uid could only be filled in *after* first sign-in — which is backwards: it
  would mean the first person to sign in with any address is the one who gets the
  restaurant. So the grant is made to an address, and the OTP is how someone proves
  they control it.
- **There is no vendor signup, deliberately.** A `restaurant_staff` row is created by
  ops, and until the admin dashboard exists (PM §8) that means SQL. A signed-in user
  with no row lands on "Not a partner account" — a screen, not an error: a customer who
  installed the wrong app has done nothing wrong, and "sign-in failed" would send them
  round the login loop forever.
- **The OTP is mailed to any address that asks, without checking staff first.** The
  check has to come *after* sign-in. A "not a partner" answer before the code is sent
  would be an oracle — anyone could type addresses until one worked, and the ones that
  work belong to people who can accept orders.
- **A vendor cannot `update` an order. At all.** There is no update grant on `orders`;
  `set_order_status` is the only way in, and the only column it can reach is `status`.
  RLS can say *which rows* a caller may write but not *which columns*, and an update
  policy that lets a restaurant set `status` is one typo away from letting it set
  `total`. The party being paid must not be able to change what it is paid. Verified:
  `update orders set total = 1` as the vendor returns **UPDATE 0**.
- **The status machine lives in the database, and the button mirrors it.** No skipping
  (nothing that was never cooked is out for delivery), no going backwards (a customer
  told their food is coming must not watch it return to the kitchen), and no cancelling
  once it is with the rider — that is a refund conversation. The Dart `next`/`canCancel`
  getters mirror the transition table so the button offers what the database will
  accept; when they disagree, the database wins and the ticket shows its sentence.
- **`OrderStatus` is duplicated, not shared.** The contract both apps answer to is the
  `orders.status` check constraint — the schema, not a Dart file. A third package to
  hold six strings would mean refactoring every import in the customer app for a new
  place to disagree with Postgres.

**Menu management is live (2026-07-15).** `/menu`, one tap from the queue: the
restaurant's own menu grouped into its sections (including the sold-out dishes a
customer cannot see), a per-dish availability switch, an add/edit sheet, and remove.
Migration 0010 grants the vendor the three write verbs 0009 withheld — insert, update,
delete — each scoped to their own restaurant by `staff_restaurant_id()`. Verified live
against Postgres: a vendor's own-menu insert succeeds; the same insert aimed at another
restaurant, and a customer's insert (no staff row → null restaurant), are both refused
by the row-level policy.

Decisions worth remembering:
- **A menu write is safe where an order write was not.** 0009 kept a vendor off `orders`
  because *the party being paid must not change what it is paid*. A menu price is the
  opposite: it is the vendor's own number, and `place_order` freezes it onto the order at
  checkout — editing a dish changes the *next* order, never a past one, because
  `order_items` denormalizes name and price (0003). So insert/update/delete are granted
  directly, gated by a `with check` that pins `restaurant_id` to the caller's kitchen (the
  same shape as the addresses policy) so no dish can be filed under someone else's menu.
- **The database picks a new dish's id.** `menu_items.id` gained a `gen_random_uuid()`
  default: a vendor adding a dish has no id to offer, and a client that names a primary
  key is one that can collide with or guess at another row's.
- **Remove is a hard delete that degrades to "mark unavailable".** The FK from
  `order_items.menu_item_id` (no cascade) lets a never-ordered dish be deleted cleanly and
  refuses to erase one that sits on a past order — a receipt must survive its dish. The app
  turns that refusal (`23503`) into a sentence pointing the vendor at the availability
  switch, which is how a dish with a history leaves the menu (0002). `order_items` and the
  customer app are untouched.
- **The availability switch is optimistic.** A kitchen marking a dish sold out mid-rush
  cannot wait on a round trip, so the switch flips first and the write confirms it; a
  refusal puts it back and says why, because a screen reading "Sold out" over a dish that
  is still selling is the one lie this screen must not tell.

**Still owed here** (the rest of the restaurant app): an open/closed switch, order
history, and the restaurant's own profile. Menu management has no photo upload — that
needs a CDN this project does not have (PM §6) — and has been verified in widget tests
and against the live database, but not yet on the Android 10 device. **Blocked, not
deferred:** payouts, commission and settlement — PM_CHECKLIST §4 has no answer for the
commission model, the settlement cadence, or the bank account, and those are not numbers
to invent.

### Step 9 — Dining (table reservations) — **new scope, 2026-07-10**
Zomato-dining / Swiggy-Dineout style: browse restaurants that take bookings, pick a
date + time slot + party size, confirm, and see/cancel upcoming bookings. Same
frontend-first discipline: a mock `DiningRepository` (slot inventory, booking rules)
first, UI against it, HTTP swap later. Surfaced as its own tab or a Food/Dineout
switcher on Home — decide when the slice starts. Open product questions for the PM
are in the pre-kickoff checklist (deposits? cancellation window? which restaurants?).

---

## Explicitly deferred

Not "forgotten" — decided against, for now, with the reason:

| Deferred | Reason |
|---|---|
| iOS | Android-first is the stated constraint; the Flutter layer is portable |
| Vendor and rider apps | Separate apps; the customer app is the product risk |
| Admin dashboard | Web, different stack, no dependency on this work |
| Grocery / quick-commerce | Food is the wedge; the catalog model generalises later |
| Ratings, referrals, wallet, subscriptions | Post-MVP revenue features |
| Proxima Nova | Paid license. Figtree ships until someone buys it; the swap is one line |
| Animated cycling search hint | Nice, ~40 lines, needs a timer whose lifecycle must be right. Cheap to add once the search screen exists |

---

## Motion & performance standard

"Butter smooth" is a budget, not a vibe. Every slice holds to:

- **Animate transforms and opacity, not layout.** `AnimatedScale` over `AnimatedContainer`
  on hot paths.
- **`RepaintBoundary` per list item** so one tile's press doesn't repaint the row.
- **Decode images at display size.** A rail of 16 full-resolution bitmaps is the classic
  Android scroll-jank source.
- **Never `Opacity` inside a scrolling body** — it forces a save-layer. Use
  `AnimatedOpacity` on leaves, or a shader.
- **Slivers, not one big `Column` in a `ScrollView`.** Off-screen sections must cost zero.
- **Motion tokens only** (`ZopiqDurations`, `ZopiqCurves`). No ad-hoc `Duration`s.

The check, before merge: run on the Android 10 device with the performance overlay
enabled, scroll the full screen top to bottom, and see no red bars.
