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

## Phase 3 — Menu & availability  ⬜

- [ ] Categories: create/edit/delete/reorder/enable-disable (`ReorderableListView`)
- [ ] Item extras: prep time, discounted price, bestseller toggle, food type, out-of-stock reason
- [ ] Variants (Half/Full, sizes) and add-on groups (min/max/required)
- [ ] Quick out-of-stock without opening the editor
- [ ] Item availability schedules (breakfast/lunch/dinner)
- [ ] Restaurant hours + pause-with-reason
- **Backend:** migrations `0015` (menu structure), `0016` (restaurant ops/hours).
- **Deps:** none.

## Phase 4 — Dashboard / home  ⬜

- [ ] New Home tab: KPI tiles (today's orders/revenue/AOV), status breakdown, recent orders
- [ ] Quick actions, alerts / pending actions, menu-availability summary
- [ ] Wire bottom nav to 5 items (Home added)
- **Backend:** mostly derived from existing streams + Phase-1 entity. **Deps:** none.

## Phase 5 — Payments & settlements  ⬜

- [ ] Earnings views (today/week/month), deductions, net, pending/completed settlements
- [ ] Settlement history + detailed breakdown (read-only frontend)
- **Backend:** migration `0017` (`settlements`, `settlement_orders`; ops/cron writes).
- **Deps:** `fl_chart` (approval needed).

## Phase 6 — Offers, analytics, ratings & reviews  ⬜

- [ ] Vendor-scoped offers: view active/upcoming/expired, create/toggle
- [ ] Analytics: revenue/order trends, top/low items, peak hours, rating trends
- [ ] Reviews: overall, distribution, recent, food/packaging sub-ratings
- **Backend:** migrations `0018` (offers), `0019` (reviews + rating aggregate trigger).
- **Deps:** `fl_chart` (approval needed).

## Phase 7 — Notifications & support  ⬜

- [ ] In-app notification center (read/unread, mark-all, deep links) — **no deps**
- [ ] Sound + haptic on new order (foreground) — **no deps**
- [ ] Background push (FCM) — **deps: firebase_messaging + flutter_local_notifications (approval)**
- [ ] Support tickets (create, list, conversation) + FAQ
- **Backend:** migrations `0020` (notifications + FCM tokens + new-order trigger), `0021` (support).

## Phase 8 — Staff roles & delivery-partner workflow  ⬜

- [ ] `restaurant_staff.role` (owner/manager/order_manager/kitchen); gate bank/settlements to owner
- [ ] Delivery-partner domain: riders, assignment, ETA, pickup status, handover OTP
- **Backend:** migration `0022` (roles) + net-new delivery schema/RPCs. Largest backend effort.

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
