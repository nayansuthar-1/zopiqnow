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
| Favourites is a dead tap | Wiring buttons to nothing is worse than leaving them inert | With the profile service |
| Recent searches vanish on restart | `shared_preferences` landed in Step 5, so this is now a wiring job through `KeyValueStore`, not a dependency decision | Next time Search is touched |
| ~~No auth, no real location~~ | ✅ Shipped in Step 5 (this table previously said "Steps 6 and 7", contradicting the build order) | done |
| ~~"Proceed to checkout" only explains itself~~ | ✅ Now opens the auth-guarded `/checkout` | done |
| OTP accepts a fixed code | No backend and no SMS provider. The mock enforces the real rules (TTL, attempt cap) so the UI is built against the true contract | Step 7 |
| Access tokens are never refreshed | Nothing calls an authenticated endpoint yet | Step 7, with the Dio interceptor |
| `kotlin.incremental=false` | Gradle 9.1.0 + Kotlin 2.3.20 cannot release their incremental caches on Windows; the build fails outright without it. Costs full Kotlin recompiles | Next Gradle/Kotlin upgrade |
| Delivery fee and tax are hardcoded | Real fees depend on distance/surge; real tax on HSN category. Isolated in `CartBill` | Step 6 |

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
without discovering new failure modes. Saved addresses are seeded rather than
per-user; there is no add/edit-address screen and no Places autocomplete. Access-token
refresh-on-401 arrives with the Dio interceptor, as nothing calls an authenticated
endpoint yet.

`/checkout` is a **stub**: it confirms *who* is ordering and *where* it goes — the two
things this step exists to establish — and says plainly that payment arrives next. It
is the guard's destination, not Step 6's screen.

### Step 5.5 — Home first-impression revamp ← **next**
The homepage must *stop* someone in the first second. Reference: Zomato's home for
the attraction (clean, modern, one bold full-bleed hero) and Swiggy for the layout
that already exists below it.

- **Hero header.** Full-bleed promo hero behind the location/search header — bold
  campaign headline, a single CTA, subtle looping motion (transform/opacity only,
  per the performance standard). Until brand art is supplied, ship a **temporary
  in-app composition** (gradient + typography + existing dish photos), built so the
  final image is a one-asset swap.
- **Keep everything below** (category rail, filters, restaurant list) — this step
  restyles the top of the feed, it does not rebuild the feed.
- Verify: cold-open on the Android 10 device, hero animates with no red bars.

### Step 6 — Checkout + payments
Address selection, coupon application, order placement, Razorpay (UPI/COD).
First step that genuinely needs a backend.

### Step 7 — Backend wiring
Swap each mock data source for its HTTP implementation, one repository at a time. If
the domain layer was respected, no widget changes. This step is the test of whether it
was.

### Step 8 — Order tracking
Live status, driver location stream, tri-tracking map.

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
