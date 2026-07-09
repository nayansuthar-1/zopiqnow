# Zopiqnow — Development Plan

**Status date:** 2026-07-09
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
| Category icons are generated placeholder art | Swiggy's illustrations are copyrighted; layout is legally reproducible, artwork is not | Before any public build |
| Restaurant images are deterministic gradients | No CDN, no image pipeline | Step 5 |
| Search bar, profile, favourites are dead taps | Home was the step; wiring dead buttons to nothing is worse than leaving them | Steps 4 and 7 |
| No auth, no real location | Nothing depends on them yet | Steps 6 and 7 |
| "Proceed to checkout" only explains itself | Checkout needs an address and a payment provider. A snackbar saying so beats a button that silently does nothing | Step 6 |
| Delivery fee and tax are hardcoded | Real fees depend on distance/surge; real tax on HSN category. Isolated in `CartBill` | Step 6 |

---

## Build order

### ~~Step 1 — Finish the menu + cart slice~~ ✅ done
Verified on device: tap a card → menu → ADD → cart bar → correct total.

### Step 2 — Bottom navigation shell ← **next**
Home / Search / Cart / Account, with `IndexedStack` so tab state survives switches, and
`StatefulShellRoute` in `go_router`. Cheap now, painful to retrofit after four screens
assume they own the `Scaffold`.

**Verify:** scroll Home, switch tabs, come back — scroll position intact.

### Step 3 — Real artwork + image pipeline
The largest *visual* jump available, and it unblocks the "looks like Swiggy" goal.

- Supply licensed category illustrations → set `FoodCategory.imageAsset`. The rail
  already reads it; nothing else changes.
- Cached network images for restaurant/dish photos, decoded at display size
  (`cacheWidth`), with the shimmer as the placeholder.

**Verify:** scroll Home and a long menu on an Android 10 device with the performance
overlay on. No frame over 16ms.

### Step 4 — Search
Query the mock repository; debounced; recent searches; results reuse `RestaurantCard`.
Makes the search bar and its tab real.

### Step 5 — Auth + location
OTP flow, token storage, `go_router` redirect guards. Device location + address
picker replacing the hardcoded `Banjara Hills, Hyderabad`.
Do this **before** checkout — checkout without a real address is a fiction.

### Step 6 — Checkout + payments
Address selection, coupon application, order placement, Razorpay (UPI/COD).
First step that genuinely needs a backend.

### Step 7 — Backend wiring
Swap each mock data source for its HTTP implementation, one repository at a time. If
the domain layer was respected, no widget changes. This step is the test of whether it
was.

### Step 8 — Order tracking
Live status, driver location stream, tri-tracking map.

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
