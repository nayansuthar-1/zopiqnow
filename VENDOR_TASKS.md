# Zopiqnow Vendor App — Build Tracker

A living checklist for turning `apps/vendor` into a complete, production-grade
restaurant-partner app (Zomato-Partner-inspired workflow, original UI). Update
the checkboxes and the **Progress log** as work lands so any session can resume.

> **How to use:** work top-down by phase. Each phase leaves the app building and
> shippable. Tick tasks as they land; note the commit in the Progress log.

---

## Ground rules (do not violate)

- **Architecture stays.** Feature-first Clean Architecture + Riverpod + go_router
  + Supabase. Every vendor write is a `security definer` RPC, **never** a table
  `UPDATE` grant. The database is the trust boundary; the client is never trusted
  for money, status, or authorization.
- **Version freeze.** No new dependency / SDK / tool version without an explicit
  approved task. New deps flagged per phase below.
- **Clean, premium UI.** Restrained and calm — the quiet-money look. Use `zopiq_ui`
  tokens/components, one brand orange (#FC8019) used sparingly, muted secondary
  text, generous whitespace, subtle motion. **No glowing icons, no glowing/gradient
  backgrounds, no neon, no gimmick effects.** Simpler and calmer when in doubt.
- **Migrations** applied directly (standing permission). Any migration touching the
  shared `orders` / `place_order` / `restaurants` surface must be reviewed with the
  user first, because the customer app reads the same rows.
- **Every phase:** `flutter analyze` clean + `flutter test` green before commit;
  commit as Nayan on `main`, then push.

---

## Decisions locked

- Delivery flow → **full pipeline + delivery-partner domain** (rider, assignment,
  pickup-OTP). Net-new backend; lands in **Phase 8**.
- Keep 6 order statuses until Phase 2 adds the kitchen-controllable ones.
- Net-new backend domains (settlements, reviews, staff roles, offers, notifications,
  delivery) each follow the established RPC + `staff_restaurant_id()` pattern.

## Dependency approvals still needed (ask before use)

- `fl_chart` — Phases 5 & 6 (charts). **Not yet approved.**
- `firebase_messaging` + `flutter_local_notifications` — Phase 7 (background push).
  **Not yet approved.** In-app notification center + sound-on-new-order need no deps.

## Navigation target

Bottom nav (max 5): **Home · Orders · Menu · History · More**.
`More` is a hub → Payments, Analytics, Offers, Reviews, Notifications, Support,
Restaurant Settings, Staff, Sign out. Notifications also gets an app-bar bell.

---

## Phase 1 — Stabilize & complete existing ✅ DONE (commit `805f66e`)

- [x] `core/formatting/formatRupees` (Indian grouping), shared
- [x] Widen `VendorOrder` with `subtotal / deliveryFee / taxes / discount` (already in the row)
- [x] `fetchHistory` — date-bounded, finished-orders read (separate from live stream)
- [x] Reusable `core/widgets`: `VendorMessage`, `VendorSkeletonList`; `OrderStatusBadge`
- [x] History rebuilt: range windows (today/yesterday/7/30/custom), outcome + payment
      filters, debounced id search, period summary, skeleton/empty/error states
- [x] Order-detail bottom sheet with full bill breakdown; tappable history tickets
- [x] Tests: 5 new History tests; `flutter analyze` clean, 29/29 green
- No migration, no new dep, no customer-app coordination.

## Phase 2 — Real-time order management  🟡 MOSTLY DONE

**Slice A (vendor-only, no migration) — DONE (`eba8118`):**
- [x] `VendorOrder.etaMinutes` (existing `orders.eta_minutes` column) + `isLate`
- [x] Delayed-order flag on live tickets — clean red `Late · Xm` pill, updates on the 30s clock

**Slice B (statuses) — DONE (customer tolerance `1a9ca66`; migration 0014 applied):**
- [x] New statuses `ready_for_pickup` + `rejected` (customer app made tolerant first)
- [x] Migration `0014`: widened `orders.status` check, `status_reason` column,
      `set_order_status(text,text,text)` with new transitions — applied + verified
- [x] Vendor flow: `ready_for_pickup` step ("Mark ready" → "Hand to rider"),
      reject-with-reason (required preset) on new orders, cancel-with-reason
      (optional) after acceptance; status badge + history include rejected

**Phase 2 leftovers — DONE (migration 0015):**
- [x] Prep-time confirm + countdown: accepting opens a prep-time sheet (10/15/20/
      30/45 min); migration `0015` adds `orders.ready_by` and stamps it via
      `set_order_status(...,p_prep_minutes)`. Ticket shows a `Ready in Xm` chip
      (orange) flipping to red `Over by Xm` past the promise, on the 30s clock.
- [x] History: `Rejected` outcome chip added.
- [x] Duplicate-guard / offline audit: guards already solid (per-order busy set in
      `OrderActionController.move`; modal sheets block re-tap; buttons disabled on
      busy). Queue + History both have error→Retry states. No code change needed.
- **Note:** `refunded` deferred to the payments phase.

**Phase 2 is complete.**

## Phase 3 — Menu & availability  ✅ DONE

**Slice 1 — Categories management — DONE (migration `0016`):**
- [x] Sections screen (`ReorderableListView`): drag to reorder, rename, enable/
      disable a whole section. Reached from the Menu app bar (swap-vert), pushed
      over the Menu tab like the profile editor. Optimistic with revert-on-refusal.
- [x] Migration `0016`: `menu_items.category_available` (default true) + customer
      read RLS widened to `is_available and category_available` — non-lossy
      (per-dish `is_available` untouched), zero customer-app code change (the
      customer leans entirely on the RLS). Reorder stamps `category_rank`, rename
      rewrites `category` across the section, both via the existing 0010 update grant.

**Slice 2 — Variants & add-ons — DONE (migration `0048`).**
- [x] One idea, not two: a group with (min 1, max 1) *is* a variant, anything else
      is add-ons — no `type` column deciding behaviour. `set_menu_item_options`
      swaps a dish's whole customisation in one transaction; `place_order` prices
      `base + Σ price_delta` and **fills a required group with its cheapest option**
      rather than refusing, so an options-unaware client still checks out.
- [x] Vendor: `DishCustomizationPage` behind the editor's Customisation row.
      Customer: `dish_options_sheet`, radios for variants, checkboxes for add-ons.

**Slice 3 — Hours — DONE (migrations `0018`, `0036`).**
- [x] `restaurant_hours` (one row per open day, absence = closed), wholesale
      `set_restaurant_hours`, `restaurant_is_open_now` as `place_order`'s gate.
      `0036` widened it to windows that cross midnight. Editor at More → Hours.

**Slice 4 — Merchandising extras, serving windows, pause-with-reason — DONE
(migration `0068`):**
- [x] Bestseller toggle (the `is_bestseller` column has existed since 0002; the
      vendor finally sets it, and the customer tile already rendered the badge).
- [x] **Struck-through "was" price** (`menu_items.original_price`). **Display
      only — never charged.** `place_order` prices every line off `price` and does
      not read the column; the check constraint refuses anything not *above* the
      live price. Nothing computes it from `price` — the vendor types it, and the
      editor says under the field who gets charged what. Flagged to the user: a
      "was" price nobody ever paid is a misleading price claim under the CCPA's
      2022 guidelines and reads as an MRP claim under Legal Metrology; the
      exposure is the restaurant's and the platform's.
- [x] Out-of-stock reason (`unavailable_reason`). Kitchen-facing only — an
      unavailable dish is already invisible to customers. The availability switch
      stays **one tap and asks nothing**; the reason is offered *afterwards*, as an
      "Add reason" row that appears under a sold-out dish, with four presets.
- [x] Per-item prep time (`prep_minutes`, 1–240). Shown on the vendor row and on
      the customer's dish tile.
- [x] **Item serving windows** (`serve_from` / `serve_to`, both-or-neither, zero
      length refused). Enforced in both places, the shape the rest of the schema
      uses: customer read RLS hides an out-of-hours dish (zero customer-app work
      required), and `place_order` refuses it with its own sentence — because RLS
      is bypassed inside a definer function, and a cart built at 10:55 is still a
      cart at 11:05. Midnight-crossing windows work, per `0036`'s logic.
- [x] **Pause-with-reason** (`restaurants.pause_reason`). `set_accepting_orders`
      gained a `p_reason` arg — the **one-arg signature was dropped**, not left to
      become an overload. Reopening clears the reason *in Postgres*, so a stale
      "power cut" cannot outlive the power coming back. Pausing asks why (four
      presets + "without saying why"); reopening never asks. The customer sees the
      kitchen's own sentence on the card scrim, the menu banner, and in
      `place_order`'s refusal.
- **Known gap, flagged not fixed:** `place_order` has never checked
  `category_available`, so a stale cart can still order from a section the vendor
  switched off (0016). Same class as the hole 0068 closes; left alone deliberately.
- **Deps:** none.

## Phase 4 — Dashboard / home  ✅ DONE

- [x] New Home tab: KPI tiles (orders today, revenue today, in the queue, delivered
      today), weekly earnings card, active-orders card
- [x] Quick actions (Menu, History, Payments, Analytics)
- [x] Bottom nav wired to 5 items — Home · Orders · Menu · History · More
- **Not built, and not missed:** AOV, and the menu-availability summary. Neither
  earned its tile beside four numbers a kitchen actually reads mid-service.
- **Backend:** derived from existing streams, as planned. No migration.

## Phase 5 — Payments & settlements  ✅ DONE

- [x] Earnings views, deductions, net, pending/completed settlements
- [x] Settlement history + detailed breakdown (`settlement_detail_page.dart`),
      read-only
- **Backend:** `settlements` / `settlement_orders`, rolled up weekly (see B7).
- **Deps:** `fl_chart` 1.2.0 — approved and pinned in `apps/vendor/pubspec.yaml`.

## Phase 6 — Offers, analytics, ratings & reviews  ✅ DONE (with B6, migrations `0062`–`0065`)

- [x] Vendor-scoped offers — `coupons.restaurant_id` (null = platform), scope enforced
      in the database; the `<restaurant id>-…` code prefix is reserved to that kitchen
- [x] Analytics: revenue/order trends, top/low items, peak hours (`hourly_bar_chart`)
- [x] Reviews room: overall, distribution histogram, recent, keyed by order id and
      **never** showing the customer
- **Backend:** `0062`–`0065`, not the `0018`/`0019` guessed here — reviews are keyed by
  order, not by (customer, restaurant), because reviewing is a thing you do to a meal.

## Phase 7 — Notifications & support  🟡 MOSTLY DONE

- [x] In-app notification center (read/unread, mark-all, deep link to queue) — **no deps**
      (migration `0021`; `features/notifications`; Home header bell + More hub row)
- [ ] Sound + haptic on new order (foreground) — **no deps**
- [x] Background push (FCM) — device + send side committed; user still owes deploy (see roadmap memory)
- [x] Support tickets → shipped as FAQ + contact (`features/support`)
- **Backend:** migrations `0020` (FCM tokens), `0021` (notifications table + read RPCs + new-order trigger).

## Phase 8 — Staff roles & delivery-partner workflow  🟡 8a DONE

**Slice 8a — Staff roles — DONE (migration `0024`):**
- [x] `restaurant_staff.role` — **two roles, `owner` + `staff`**, not the four
      originally sketched. Four roles where three of them gate nothing identical
      is a distinction the UI would have to fake; two each gate something real.
      Widening the check constraint later adds more without changing any existing
      row's meaning. Default `owner`, so every pre-0024 row backfills to full
      access and nobody loses anything the day it lands.
- [x] Gated to owner, **in Postgres**: the `settlements` select policy, the
      `vendor_earnings_summary` RPC, and all four staff-management RPCs.
      Deliberately *not* gated: orders, menu, hours, profile, analytics — the
      line is drawn around money and access, not around the working day.
- [x] `staff_role()` helper (twin of `staff_restaurant_id()`); `Vendor.role`
      resolved at sign-in and defaulting to least privilege on a failed read.
- [x] Owner-only in the app: More → Team, More → Payments, Home's weekly earnings
      card and Payments shortcut. Hidden, not greyed — a "Soon" chip means the
      app owes you this, a dead row would mean *you personally* may not.
- [x] `features/staff`: roster (owners first), add by email with a role, promote/
      demote, remove — each behind a confirm, none optimistic.
- [x] **An owner may not act on themselves.** Written against the self-lockout
      footgun; it also proves the property that would otherwise need its own
      check — since the caller is always an owner and always untouchable, no
      sequence of calls can leave a restaurant with zero owners.
- [x] Verified against the real database (psql, in a rolled-back transaction):
      backfill, every refusal, and that staff keep orders + menu writes.
      Vendor 58/58 green, analyze clean.

**Slice 8b — Delivery partners — 🟡 IN PROGRESS.** Planned in full in
[`DELIVERY_PLAN.md`](DELIVERY_PLAN.md); user chose a **platform-wide fleet** and a
**rider app** in this phase.
- [x] **8b-1 — the domain + the vendor's half (migration `0025`).** Riders,
      self-claim dispatch, pickup-OTP handover. No new `orders.status` values and
      no new policy on `orders`. Rider strip on the ticket. Vendor 62/62 green.
- [x] **8b-2 — `apps/rider`**, a fourth workspace member, no new deps. Email-OTP
      auth, the job board, claim/drop, the pickup-code handover, delivery.
      12/12 green; debug + release APKs build. First partner seeded (`seed/0006`).
- [ ] 8b-3 — the customer sees their rider on the tracking card.
- [ ] 8b-4 — hardening: `/security-review`, the edge matrix, optional auto-assign.

## Phase 9 — Perf, security, hardening  ⬜

- [ ] Rebuild/scroll profiling; pagination audits; image caching
- [ ] `/security-review`; RLS/RPC audit for every new write
- [ ] Edge-case matrix (offline mid-accept, dup status, app-killed-on-order, resume-from-bg, etc.)
- [ ] Test coverage pass

---

## Progress log

- **2026-07-17** — Analysis + phased plan approved. Phase 1 completed and pushed
  (`805f66e`): History rebuilt with filters/search/summary/detail sheet; `VendorOrder`
  widened; reusable widgets + `formatRupees` added. Analyze clean, 29/29 tests green.
- **2026-07-17** — Phase 2 Slice A: `etaMinutes` + `isLate` on `VendorOrder`; clean
  `Late · Xm` pill on overdue live tickets. No migration. Analyze clean, 30/30 green.
- **2026-07-17** — Phase 2 Slice B: customer app made status-tolerant (`1a9ca66`);
  migration `0014` applied (ready_for_pickup, rejected, status_reason, new transitions);
  vendor got the ready step + reject/cancel-with-reason. Vendor 31/31 green, analyze clean.
  Customer app: 4 pre-existing `ListTile`-in-`DecoratedBox` test failures (SDK assertion,
  unrelated to this change) — flagged, not fixed.
- **2026-07-17** — Phase 2 leftovers: migration `0015` (`ready_by` + prep-time param);
  prep-time sheet on accept + `Ready in Xm`/`Over by Xm` countdown chip; History `Rejected`
  chip; guard/offline audit (no change needed). Phase 2 complete.
- **2026-07-20** — Phase 7 in-app notification center. New `features/notifications`
  (entity/datasource/providers/page). Migration `0021`: `notifications` table
  (per-restaurant, RLS-scoped read), `mark_notification_read` /
  `mark_all_notifications_read` RPCs (read_at-only, no update grant), an
  exception-safe `AFTER INSERT` trigger on `orders` that writes a "New order" row
  (approved — touches the shared orders surface; wrapped so it can never abort
  placement), and the table added to the `supabase_realtime` publication. Applied
  + verified (trigger writes on insert; rolled back, no prod pollution). Inbox at
  More → Notifications, plus a live unread bell in the Home header; tap deep-links
  to the queue. Vendor 47/47 green, analyze clean.
  - **Pre-existing breakage found & fixed:** commit `490505f` ("ui changes in
    vendor") had left `main` **not compiling** — its import cleanup dropped
    `auth_providers` from `queue_page` (used `vendorProvider`) and `router` from
    `home_page` (used `Routes`); re-added both. That same commit's new
    `StoreStatusBanner` ran a perpetual `..repeat()` pulse that hung every widget
    test's `pumpAndSettle`; now gated on reduced-motion, and the test harness sets
    `disableAnimations`. Two queue-header assertions (restaurant name → now a fixed
    "Active Orders" title; live name moved to the Home header) updated to match the
    redesign. (These had never run because the commit didn't compile.)
- **2026-07-21** — Phase 8a (Staff roles). Migration `0024` applied: `role` on
  `restaurant_staff` (`owner`/`staff`, default `owner` so the backfill costs
  nobody access), `staff_role()`, the settlements policy and
  `vendor_earnings_summary` narrowed to owners, and four owner-only RPCs
  (`list_restaurant_staff`, `add_restaurant_staff`, `set_staff_role`,
  `remove_restaurant_staff`). Scope decision: **two roles, not four** — a role
  that gates nothing is a lie the UI tells. An owner adds colleagues in-app,
  which does not reopen 0009's self-service hole: the caller already holds the
  authority being granted and can only grant it inside the one restaurant they
  already run; an address on another team is refused, never reassigned. New
  `features/staff` (Team screen) + owner-only Payments/Team rows in More and on
  Home. Every guard exercised against the real database inside a rolled-back
  transaction, including the negative cases (staff keep orders and menu writes).
  Vendor 58/58 green, analyze clean.
- **2026-07-30** — Phase 3 closed. Migration `0068` applied and verified against
  the real database (psql, rolled-back transactions): the five new `menu_items`
  columns and their constraints, `menu_item_is_servable_now` (normal *and*
  midnight-crossing windows, both edges), the widened customer read policy (anon
  sees the dish, loses it outside its window, gets it back inside), `place_order`
  refusing an out-of-window line by name while an in-window one goes through,
  `original_price` provably not reaching the charged unit price, the pause refusal
  carrying the kitchen's own sentence, and `set_accepting_orders` clearing the
  reason on reopen + truncating at 120 chars. Function list checked for
  overloads — exactly one signature each. Vendor analyze clean; customer analyze
  shows only pre-existing warnings in the user's WIP files.
  - **A note on the "was" price:** the user's decision is that it is a marketing
    device, not a real former price. Built as a plain vendor-typed column with a
    display-only guarantee enforced in `place_order`; nothing fabricates or infers
    the number. The legal exposure (CCPA misleading-advertisement guidelines,
    Legal Metrology) was raised with the user before building.
  - **Pre-existing quirk found, not fixed:** two successful `place_order` calls
    cannot share one transaction — its `_lines` temp table is `on commit drop`.
    Harmless for real clients (one call per transaction), a trap when testing.
- **2026-07-17** — Phase 3 Slice 1 (Categories management): new Sections screen —
  reorder (drag), rename, enable/disable a whole section — reached from the Menu app
  bar, optimistic with revert-on-refusal. Migration `0016` applied: `category_available`
  column (default true) + customer read RLS widened to `is_available and category_available`
  (non-lossy, zero customer-app change). Vendor 37/37 green, analyze clean.
