# Audit remediation checklist

Every finding in `AUDIT_REPORT_2026-07-30.html`, as boxes you can tick.

**The HTML report is the source of truth, not this file.** This is a working
view of it: the same IDs, the same severities, the same effort estimates, sorted
so the next thing to pick up is near the top. When you close something, update
the finding's own `<details>` body in the report *and* tick it here. If the two
ever disagree, the report wins — it is the document with the reasoning in it.

The report is **untracked** and is not in git, so a fresh clone has this file and
not the thing it describes.

Convention this repo has used since 2026-07-30: **one finding, one commit**,
subject line `fix(<area>): <lowercase sentence> (audit <ID>)`.

🔸 marks a finding **no commit can close** — a dashboard toggle, a key rotation, a
KYC application, a purchase. They are in the list because they are launch gates,
not because they are codeable.

---

## At a glance

| | Open | Closed |
|---|---:|---:|
| 🔴 **Blocker** — launch gate | 2 | 12 |
| 🟠 **Critical** | 25 | 8 |
| 🟡 **Major** | 46 | 5 |
| ⚪ **Minor** | 12 | 1 |
| | **85** | **29** |

> **Re-verified 2026-08-07 against the running code and the live database.** Six
> findings were already fixed and never ticked — REL-001, OBS-001, PAY-001,
> RID-005, SEC-005, and half of SEC-003. Each was checked against the artefact
> rather than the source: signing read out of the built APK with `apksigner`,
> the payment gate read out of `payment_settings` over psql. **A tracker that
> over-reports open work is as misleading as one that under-reports it** — it
> hides the two blockers that are real behind four that are not.

1 finding withdrawn by the auditor. **115 carry an ID of their own.**
The report's own headline count is 118; the difference is findings folded into
another's recommendation list rather than registered separately — `UI-002`
(no adaptive icon on the vendor and rider apps, folded into **UI-001**) and
`FUN-005` (double-tap, closed by **FUN-002**'s idempotency key). Neither has a
severity or an effort of its own to sort by, so neither gets a box here.

**By effort, still open:** XS 7 · S 35 · M 35 · L 11

> **Until 6 August this file is not the queue.** `LAUNCH_PLAN_2026-08-05.md` is —
> it sorts the same findings by what blocks a Play listing on the 5th rather than
> by what costs most to leave broken over a year. Come back here afterwards.

---

## 🔴 Blockers — nothing ships until these are closed

Sorted by effort, cheapest first.

- [x] **REL-001** — All three release builds are signed with the debug keystore. **Closed — re-verified 2026-08-07 from the built artifacts, not the source:** `apksigner verify --print-certs` on each release APK returns `05:F4:0D:21…` (vendor), `E9:F8:91:57…` (rider), `A9:09:B9:1D…` (customer) — the upload certificates, each of which is registered as an Android OAuth client. All three `build.gradle.kts` carry a `signingConfigs.getByName("release")`, and debug now signs with the release cert too, so Google Sign-In behaves the same in both.<br><sub>Cross-cutting · Android build · effort S</sub>
- [x] **OBS-001** — No crash reporting, no analytics, no APM — in any of the four clients. **Closed — `firebase_crashlytics` is a direct dependency of all three Flutter apps**, and handled errors are reported deliberately (a Google sign-in failure writes the underlying code, which is otherwise only visible in `adb logcat`).<br><sub>Cross-cutting · Observability · effort M</sub>
- [ ] **ADM-001** — There is no customer management at all.<br><sub>Feature · effort L</sub>
- [ ] **FEA-001** — There is no geospatial model — "nearby" is a number an admin typed in<br><sub>Customer App · Backend · Home / Checkout · effort L</sub>
- [x] **PAY-001** — Payment is a mock, and the server accepts any string as proof of it. **Closed in code; the remaining half is 🔸 credentials.** `RazorpayPaymentGateway` is the bound gateway and falls back to the mock *only while `razorpay-order` answers `configured: false`* — so the day the keys are set, every already-installed build starts taking real payments with no release and no store review. Server side: `razorpay-verify` checks the HMAC, and the 0085 `before insert` trigger refuses an unproved order. ⚠️ **Verified against the live DB 2026-08-07: `require_verified_payment = false` and zero Razorpay secrets in Vault.** Keys first, then one `update`. Until then the trigger is disarmed and an order can be placed without payment being proved.<br><sub>Customer App · Backend · Checkout → UPI sheet · effort L</sub>

---

## 🟠 Critical

- [ ] **SEC-007** — The Resend API key remains unrotated after being committed to git history. 🔸<br><sub>Secrets · Security · effort XS</sub>
- [x] **SEC-010** — The `push_on_notification_insert` webhook stores a **`service_role` JWT in plaintext** in its trigger definition, readable via `pg_get_triggerdef` by anything that can read the catalog — a read-only foothold, a backup or a dashboard user thereby escalates to a key that bypasses RLS entirely. Not reachable through PostgREST, which exposes no catalog. **Closed 2026-08-03 by migration 0091 (ship S7): the header bought nothing** — `send-notification` is `--no-verify-jwt` and a POST with no Authorization header returns 403 from its own `x-notify-secret` check, not 401 from the gateway. The rewrite deletes one key from the existing headers rather than restating them, so the secret never entered a migration file. Verified end to end: a notification to a recipient with no devices recorded `200 "No devices"` in `net._http_response`.<br><sub>Backend · Database · webhook · Security · effort XS</sub>
- [x] **API-002** — ola-static proxies the Ola Maps key with no caller authentication or rate limit shown in its handler. **Closed 2026-08-03 by retirement, not authentication: nothing has called it since B3. Key unset from the function env (Vault routing key untouched), handler returns 410 unconditionally. **Fully closed 2026-08-03 (ship S7): the function is now deleted — a POST returns `404 NOT_FOUND` rather than the handler's 410.**<br><sub>Edge fn · Security · effort S</sub>
- [ ] **CUS-001** — Hard 25-order ceiling with no "load more".<br><sub>Order history · UX · effort S</sub>
- [x] **CUS-005** — No idempotency on place_order. **Closed 2026-08-03 (migration 0086): caller-chosen key per checkout attempt, unique per customer, retries answered with the order already placed.**<br><sub>Checkout · Functional · effort S</sub>
- [ ] **DAT-002** — A temp table is created on every order. **Second face of the same fact, found by the S4 probe 2026-08-03:** `_lines` is `on commit drop`, so `place_order` **cannot be called twice inside one transaction** — the second call dies on `relation "_lines" already exists`. Harmless in production, where every PostgREST RPC is its own transaction, but it means any test or batch that places two orders needs a savepoint per call.<br><sub>place_order · Performance · effort S</sub>
- [ ] **DAT-006** — The CLI migration ledger has drifted from the live database four times and migrations 0062–0069 show as local-only despite being applied.<br><sub>Migrations · Architecture · effort S</sub>
- [x] **RID-005** — No concurrent-claim cap and no fraud limits. **Closed — both exist and are enforced in the dispatcher, not the app.** `offer_delivery` filters candidates on `cand.live_jobs < v_s.max_live_jobs` (0099), counting deliveries in `claimed`/`arrived_at_restaurant`/`picked_up`/`arrived_at_customer`, so a rider cannot be offered work past the cap. Cash riders are additionally capped by `rider_cash_in_hand(p.email) + v_total <= rider_cash_cap()`. Velocity limits landed with 0090.<br><sub>Jobs · Business · effort S</sub>
- [ ] **SEC-004** — The Cloudinary unsigned upload preset ships inside every APK<br><sub>Customer App · Vendor App · Media · effort S</sub>
- [ ] **SEC-008** — No documented backup, PITR, or disaster-recovery plan. 🔸<br><sub>Backups · Architecture · effort S</sub>
- [ ] **ADM-004** — No manual rider assignment override.<br><sub>Live orders · UX · effort M</sub>
- [ ] **ADM-009** — No staging environment referenced anywhere, and the admin console points at the same Supabase project as the apps. 🔸<br><sub>Architecture · effort M</sub>
- [ ] **BIZ-006** — Delivery fee is subtotal >= 500 ? 0 : 40, hardcoded, distance-blind.<br><sub>Pricing · Business · effort M</sub>
- [ ] **CUS-002** — Whole restaurant table fetched per home load, ordered by a fictional distance column.<br><sub>Home · Performance · effort M</sub>
- [ ] **CUS-003** — Search is unbounded ilike '%q%' on search_text.<br><sub>Search · Functional · effort M</sub>
- [ ] **CUS-027** — No order-level fraud controls.<br><sub>Order tracking · Business · effort M</sub>
- [ ] **PERF-002** — Nothing is paginated — two .limit() calls exist in the entire product<br><sub>Customer App · Vendor App · Data layer · effort M</sub>
- [ ] **QA-001** — The money layer has no tests, the suite is red, and nothing runs it<br><sub>Cross-cutting · Quality · effort M</sub>
- [ ] **RID-003** — No proof of delivery beyond the OTP.<br><sub>Delivery · Functional · effort M</sub>
- [ ] **RID-008** — No SOS button, no emergency contact, no accident reporting.<br><sub>Jobs · Safety · effort M</sub>
- [ ] **SEC-003** — The admin console is flat-role, password-only, with no MFA and almost no audit trail. **Half closed 2026-08-07 review:** the audit trail exists — `admin_actions` (0092), append-only via table triggers rather than by asking each RPC to remember, and the console reads it only through RPCs. **Still open: MFA, and the flat role.** Every admin can do everything, including the unguarded order delete added in 0069.<br><sub>Admin Console · Auth & RBAC · effort M</sub>
- [x] **SEC-005** — No rate limiting on any RPC. **Closed by migration 0090** — 10 orders/hr per customer, 6 broadcasts/hr, 20 chat lines per side per order. OTP is left to GoTrue's own limiter rather than duplicated. ⚠️ One property worth knowing before writing more of these: `now()` is frozen for the whole transaction, so a limiter that compares against `now()` cannot see writes made earlier in the *same* transaction.<br><sub>Rate limiting · Security · effort M</sub>
- [ ] **UX-001** — The Account screen is half dead ends — five tiles are "coming soon" snackbars<br><sub>Customer App · Account · effort M</sub>
- [ ] **UX-002** — No phone-number authentication — an Indian food delivery app that signs in by email<br><sub>Customer App · Auth · effort M</sub>
- [ ] **ADM-002** — No support ticket queue.<br><sub>Feature · effort L</sub>
- [ ] **CUS-011** — No wallet or credits system at all.<br><sub>Wallet · Feature · effort L</sub>
- [ ] **FUN-002** — No offline handling, no retry, no connectivity awareness anywhere<br><sub>Cross-cutting · Network layer · effort L</sub>
- [ ] **RID-006** — No incentives engine.<br><sub>Earnings · Business · effort L</sub>
- [ ] **UI-001** — The vendor app is portrait-locked — a restaurant POS that cannot run on a tablet in a stand<br><sub>Vendor App · Shell · effort L</sub>

---

## 🟡 Major

- [ ] **API-001** — send-order-push is still deployed and ACTIVE despite being unwired since migration 0058. 🔸<br><sub>Edge fn · Security · effort XS</sub>
- [ ] **CUS-006** — No minimum order value and no per-restaurant override.<br><sub>Checkout · Business · effort XS</sub>
- [ ] **CUS-015** — Delivery OTP is displayed unconditionally on the tracking card.<br><sub>Order tracking · UX · effort XS</sub>
- [ ] **UI-004** — Brand orange on white measures 2.55:1.<br><sub>Design system · UI · effort XS</sub>
- [ ] **VEN-006** — Settlement week is UTC-truncated (date_trunc('week', o.created_at)) while the rider payout week is IST-truncated.<br><sub>Payments · Business · effort XS</sub>
- [ ] **ADM-006** — No campaign cost or redemption reporting.<br><sub>Coupons · Business · effort S</sub>
- [ ] **ADM-007** — Broadcast to all users has no rate limit, no preview, no scheduling, and no undo — and, with a flat admin role (SEC-003), anyone with console access can send it.<br><sub>Broadcast · Security · effort S</sub>
- [ ] **ADM-008** — Order deletion is unguarded beyond an audit row.<br><sub>Orders · Security · effort S</sub>
- [ ] **BIZ-009** — Restaurant rating is trigger-computed as a simple mean with no recency weighting, no minimum-count suppression, and no protection against review bombing.<br><sub>Ratings · Business · effort S</sub>
- [ ] **CUS-009** — Cart is not re-priced on open.<br><sub>Cart · Business · effort S</sub>
- [ ] **CUS-014** — No serviceability feedback at address-save time.<br><sub>Address book · Functional · effort S</sub>
- [ ] **CUS-017** — Unbounded realtime inbox, growing for the life of the account.<br><sub>Notifications · Performance · effort S</sub>
- [ ] **CUS-024** — No "report an issue with this order" entry point, which is the natural home for the support flow UX-001 needs.<br><sub>Order detail · UX · effort S</sub>
- [ ] **CUS-026** — No OTP resend throttle or attempt cap in the app; the only limit is Supabase's project-level email rate limit.<br><sub>Auth · Security · effort S</sub>
- [ ] **DAT-003** — Order ids are a visible global sequence (ZPQ-1001, ZPQ-1002…).<br><sub>orders.id · Security · effort S</sub>
- [ ] **DAT-004** — A single hot row per rider, updated every 20–30 s.<br><sub>rider_locations · Performance · effort S</sub>
- [ ] **RID-009** — No support screen.<br><sub>Shell · Feature · effort S</sub>
- [ ] **RID-010** — A 20-second heartbeat timer calls getCurrentPosition at high accuracy whenever the last-known fix is null, in addition to the 30 m stream.<br><sub>Battery · Performance · effort S</sub>
- [ ] **RID-011** — No rider photo anywhere — the roster stores none, so the customer's tracking card shows a name and a vehicle only.<br><sub>Profile · UX · effort S</sub>
- [ ] **VEN-002** — Prep time cannot be revised after accepting.<br><sub>Queue · UX · effort S</sub>
- [ ] **VEN-007** — No dispute or hold mechanism on a settlement, and no adjustment line.<br><sub>Payments · Business · effort S</sub>
- [ ] **VEN-011** — History caps at 500 rows with no pagination and no supporting index (DAT-001).<br><sub>History · Performance · effort S</sub>
- [ ] **VEN-012** — Staff roles exist but no session or device management.<br><sub>Staff · Security · effort S</sub>
- [ ] **ADM-003** — No cohort, funnel, or unit-economics reporting, and no CSV export anywhere.<br><sub>Analytics · Business · effort M</sub>
- [ ] **ADM-005** — Most operating parameters are hardcoded in SQL — delivery fee thresholds, tax rate, the 5-minute accept timeout, commission default.<br><sub>Settings · Business · effort M</sub>
- [ ] **API-003** — No API versioning strategy.<br><sub>RPC design · API · effort M</sub>
- [ ] **API-004** — Errors are conveyed by Postgres P0001 and a human sentence.<br><sub>RPC design · API · effort M</sub>
- [ ] **ARC-001** — Three Flutter apps duplicate secure_store.dart, supabase_secure_local_storage.dart, push_service.dart and the notifications datasource with near-identical…<br><sub>Repo · Architecture · effort M</sub>
- [ ] **CUS-004** — No filters or sort.<br><sub>Search · UX · effort M</sub>
- [ ] **CUS-008** — No tipping.<br><sub>Checkout · UX · effort M</sub>
- [ ] **CUS-013** — Reverse geocoding only — no place autocomplete.<br><sub>Address book · UX · effort M</sub>
- [ ] **CUS-016** — No SOS or safety feature for the customer, and no way to report a rider mid-delivery.<br><sub>Order tracking · Functional · effort M</sub>
- [ ] **CUS-019** — No deep links or App Links.<br><sub>Cross-app · Functional · effort M</sub>
- [ ] **CUS-025** — 209 hardcoded Color(0x…) literals and 249 Colors.* references in a customer app that ships a user-selectable dark theme.<br><sub>Dark mode · UI · effort M</sub>
- [ ] **DAT-005** — orders.user_id is text, not a uuid FK to auth.users.<br><sub>Schema · Database · effort M</sub>
- [ ] **RID-004** — rider_locations stores one row per rider — the latest fix only.<br><sub>Location · Database · effort M</sub>
- [ ] **RID-007** — No shift or availability scheduling.<br><sub>Shell · Functional · effort M</sub>
- [ ] **RID-014** — Email OTP sign-in for riders, many of whom will not have a working email on their phone.<br><sub>Auth · UX · effort M</sub>
- [ ] **VEN-003** — No partial-order handling.<br><sub>Queue · Functional · effort M</sub>
- [ ] **VEN-004** — No stock or inventory count — availability is a boolean toggled by hand.<br><sub>Menu · Functional · effort M</sub>
- [ ] **VEN-005** — No cancellation or rejection metrics surfaced to the vendor, and no acceptance-rate SLA.<br><sub>Analytics · Business · effort M</sub>
- [ ] **CUS-007** — No scheduled ordering.<br><sub>Checkout · UX · effort L</sub>
- [ ] **CUS-022** — Browse-only.<br><sub>Gifts · Feature · effort L</sub>
- [ ] **UI-007** — No tablet or large-screen layouts anywhere, and no responsive breakpoints.<br><sub>All apps · UI · effort L</sub>
- [ ] **BIZ-008** — No batching or multi-pickup optimisation beyond stacked runs, and no rejection penalty.<br><sub>Dispatch · Business</sub>
- [ ] **CUS-012** — No referral programme, no loyalty tier, no subscription (Zomato Gold / Swiggy One equivalent).<br><sub>Account · Feature</sub>

---

## ⚪ Minor

- [ ] **UI-006** — Dark surface is pure #000000.<br><sub>Design system · UI · effort XS</sub>
- [ ] **API-005** — No certificate pinning in any app.<br><sub>Transport · Security · effort S</sub>
- [ ] **API-006** — No root/jailbreak detection and no tamper checks, with R8 disabled (REL-001) so the binary is trivially readable.<br><sub>Transport · Security · effort S</sub>
- [ ] **ARC-003** — Twelve overlapping planning documents at the repo root, several superseded, and three deleted in the working tree but not committed.<br><sub>Docs · Architecture · effort S</sub>
- [ ] **CUS-010** — No "add more items" shortcut back to the menu, and no upsell rail ("people also ordered").<br><sub>Cart · UX · effort S</sub>
- [ ] **CUS-023** — Status views exist (home_status_views, gift_status_views) but coverage is inconsistent across favourites, search, notifications and history.<br><sub>Empty states · UI · effort S</sub>
- [ ] **UI-005** — ~130 off-grid spacing values in the customer app against a documented 8pt grid rule — SizedBox(height: 3/6/7/10/14/18/20/28/40) and EdgeInsets.all(6/7/14/18/20).<br><sub>Design system · UI · effort S</sub>
- [ ] **VEN-008** — No holiday or temporary-closure scheduling.<br><sub>Profile · UX · effort S</sub>
- [ ] **VEN-009** — Vendor cannot reply to a review.<br><sub>Reviews · UX · effort S</sub>
- [ ] **CUS-020** — No dish images shown at list level in most sections and no "bestseller" or "must try" ranking signal.<br><sub>Menu · UX · effort M</sub>
- [ ] **CUS-021** — Rating is a sheet with no photo upload and no dish-level rating.<br><sub>Ratings · UX · effort M</sub>
- [ ] **RID-012** — Navigation is a hand-off to an external maps app, documented as a deliberate choice.<br><sub>Jobs · UX</sub>
- [ ] **SEC-009** — `REFERENCES` and `TRIGGER` are still granted to `anon` on the public tables that 0089 stripped of write privileges. Neither is reachable through PostgREST, which issues no DDL, so this is untidiness rather than exposure — the same default-ACL row is the source.<br><sub>Backend · Database · grants · effort XS</sub>

---

## Cross-cut: by effort

Reference views into the same findings above — tick the boxes there, not here.
🔴 blocker · 🟠 critical · 🟡 major · ⚪ minor.

### XS — an afternoon between them
🟠 SEC-007 · 🟡 API-001 · 🟡 CUS-006 · 🟡 CUS-015 · 🟡 UI-004 · 🟡 VEN-006 · ⚪ UI-006

### S — a day or two each
🔴 REL-001 · 🟠 API-002 · 🟠 CUS-001 · 🟠 CUS-005 · 🟠 DAT-002 · 🟠 DAT-006 · 🟠 RID-005 · 🟠 SEC-004 · 🟠 SEC-008 · 🟡 ADM-006 · 🟡 ADM-007 · 🟡 ADM-008 · 🟡 BIZ-009 · 🟡 CUS-009 · 🟡 CUS-014 · 🟡 CUS-017 · 🟡 CUS-024 · 🟡 CUS-026 · 🟡 DAT-003 · 🟡 DAT-004 · 🟡 RID-009 · 🟡 RID-010 · 🟡 RID-011 · 🟡 VEN-002 · 🟡 VEN-007 · 🟡 VEN-011 · 🟡 VEN-012 · ⚪ API-005 · ⚪ API-006 · ⚪ ARC-003 · ⚪ CUS-010 · ⚪ CUS-023 · ⚪ UI-005 · ⚪ VEN-008 · ⚪ VEN-009

### M — most of a week each
🔴 OBS-001 · 🟠 ADM-004 · 🟠 ADM-009 · 🟠 BIZ-006 · 🟠 CUS-002 · 🟠 CUS-003 · 🟠 CUS-027 · 🟠 PERF-002 · 🟠 QA-001 · 🟠 RID-003 · 🟠 RID-008 · 🟠 SEC-003 · 🟠 SEC-005 · 🟠 UX-001 · 🟠 UX-002 · 🟡 ADM-003 · 🟡 ADM-005 · 🟡 API-003 · 🟡 API-004 · 🟡 ARC-001 · 🟡 CUS-004 · 🟡 CUS-008 · 🟡 CUS-013 · 🟡 CUS-016 · 🟡 CUS-019 · 🟡 CUS-025 · 🟡 DAT-005 · 🟡 RID-004 · 🟡 RID-007 · 🟡 RID-014 · 🟡 VEN-003 · 🟡 VEN-004 · 🟡 VEN-005 · ⚪ CUS-020 · ⚪ CUS-021

### L — a sprint each
🔴 ADM-001 · 🔴 FEA-001 · 🔴 PAY-001 · 🟠 ADM-002 · 🟠 CUS-011 · 🟠 FUN-002 · 🟠 RID-006 · 🟠 UI-001 · 🟡 CUS-007 · 🟡 CUS-022 · 🟡 UI-007

---

## Cross-cut: needs a person, not a commit

Also a reference view — the boxes for these are up in the severity sections.
Six of the 93 open findings, and between them they hold up a release.

- 🔴 **PAY-001** — Blocked on Razorpay merchant KYC — a PM task. The schema and the refund ledger already wait for it.
- 🟠 **SEC-007** — Rotate the key in the Resend dashboard. Code cannot un-leak a secret.
- 🟠 **SEC-008** — Enable PITR in the Supabase dashboard, then test a restore.
- 🟠 **ADM-009** — Stand up a staging project. Money, not code.
- 🟡 **API-001** — One CLI call: `supabase functions delete send-order-push`.
- 🔴 **REL-001** — Generate real keystores and store them somewhere that is not this repo — then R8 and a full release regression.

---

## Cross-cut: where the open work lives

| Area | Open | 🔴 | 🟠 | 🟡 | ⚪ |
|---|---:|---:|---:|---:|---:|
| **Customer app** `CUS-` | 26 |  | 6 | 16 | 4 |
| **Rider app** `RID-` | 11 |  | 4 | 6 | 1 |
| **Vendor app** `VEN-` | 10 |  |  | 8 | 2 |
| **Admin console** `ADM-` | 9 | 1 | 3 | 5 |  |
| **Edge functions & RPC** `API-` | 6 |  | 1 | 3 | 2 |
| **Database** `DAT-` | 5 |  | 2 | 3 |  |
| **Security** `SEC-` | 5 |  | 5 |  |  |
| **Design system** `UI-` | 5 |  | 1 | 2 | 2 |
| **Architecture & repo** `ARC-` | 3 |  |  | 1 | 2 |
| **Money & business rules** `BIZ-` | 3 |  | 1 | 2 |  |
| **Performance** `PERF-` | 1 |  | 1 |  |  |
| **User experience** `UX-` | 2 |  | 2 |  |  |
| **Missing capability** `FEA-` | 1 | 1 |  |  |  |
| **Reliability** `FUN-` | 1 |  | 1 |  |  |
| **Legal & compliance** `LEG-` | 1 | 1 |  |  |  |
| **Observability** `OBS-` | 1 | 1 |  |  |  |
| **Payments** `PAY-` | 1 | 1 |  |  |  |
| **Testing** `QA-` | 1 |  | 1 |  |  |
| **Release engineering** `REL-` | 1 | 1 |  |  |  |

---

## ✅ Closed

Taken from the report's own "Fixed since Rev. 1.0" list, by ID. Each has a
`Resolution` block in its finding body saying what was actually done and what
was deliberately left — several closed *less* than their title suggests.

**`ARC-002` is the one to read carefully: it is closed only in part.** CI runs
analyze and all four suites; there is still no deployment pipeline.

- [x] **ARC-002** — No CI/CD pipeline of any kind.<br><sub>Repo · Architecture · Major · effort S</sub>
- [x] **BIZ-001** — Settlement pays vendors on pre-discount subtotal — a vendor can fund its own discount from your bank account<br><sub>Backend · Database · run_settlement_batch · Blocker · effort M</sub>
- [x] **BIZ-002** — Cash on delivery has no reconciliation — the platform pays out twice and collects nothing<br><sub>Backend · Rider App · Payouts · Blocker · effort L</sub>
- [x] **BIZ-003** — Coupons have no usage limit of any kind<br><sub>Backend · Database · coupons · Blocker · effort M</sub>
- [x] **BIZ-004** — There is no refund path — money that comes in never goes back out<br><sub>Backend · Customer App · Order lifecycle · Blocker · effort L</sub>
- [x] **BIZ-005** — GST is charged on the pre-discount subtotal, and the tax model has one flat rate<br><sub>Backend · place_order · Invoicing · Critical · effort M</sub>
- [x] **BIZ-007** — No hold period before settlement.<br><sub>Settlement · Business · Major · effort S</sub>
- [x] **CUS-018** — PushService.start() is awaited before runApp in customer and rider — a Firebase init, a permission prompt and a token registration round trip on the critical path…<br><sub>Splash / startup · Performance · Major · effort XS</sub>
- [x] **DAT-001** — No index on orders(restaurant_id, …) — the hottest query path in the system is a sequential scan<br><sub>Database · orders · Critical · effort XS</sub>
- [x] **LEG-001** — No account deletion, no privacy policy, no consent — three hard Play Store gates<br><sub>Customer App · Compliance · Blocker · effort M · items 4 (location rationale) and 6 (FSSAI display) deliberately left</sub>
- [x] **ARC-004** — The working tree has ~60 uncommitted modified files.<br><sub>Repo · Architecture · Minor · effort XS · main did not compile from a clone; see the report</sub>
- [x] **PERF-001** — The vendor app streams the restaurant's entire lifetime order history, forever, over a websocket<br><sub>Vendor App · Queue & Dashboard · Blocker · effort S</sub>
- [x] **FUN-001** — Every vendor-created offer shown at checkout is rejected when tapped — the feature has never worked end to end<br><sub>Customer App · Checkout → Offers strip · Critical · effort XS</sub>
- [x] **QA-002** — Twenty-seven tests fail on main — across all three apps.<br><sub>Test suite · Functional · effort M</sub>
- [x] **QA-003** — The map view constructed its animation controller inside dispose().<br><sub>zopiq_map · Functional · effort XS</sub>
- [x] **RID-001** — Rider location has no foreground service — live tracking stops the moment the rider opens their maps app<br><sub>Rider App · Location reporter · Blocker · effort S</sub>
- [x] **RID-002** — No KYC.<br><sub>Onboarding · Business · Blocker · effort L</sub>
- [x] **RID-013** — App label is zopiq_rider — the raw package name shows on the launcher and in the app switcher.<br><sub>Shell · UI · effort XS</sub>
- [x] **SEC-001** — The push notification Edge Function authenticates nothing — anyone can notify any user<br><sub>Backend · supabase/functions/send-notification · Blocker · effort XS</sub>
- [x] **SEC-002** — 51 security definer functions were never revoked from PUBLIC. **Recurred, and re-closed 2026-08-03 by migration 0087: six more had arrived by then, one per recent migration, because functions here are *born* with PUBLIC EXECUTE and `alter default privileges` does not prevent it. One was a live hole — `order_receipt_by_key`, callable unauthenticated with the anon key. This finding is a standing rule, not a one-off sweep: see `SHIP_PLAN_ANDROID_IOS.md` S1.**<br><sub>Backend · Database · grants · Critical · effort S</sub>
- [x] **SEC-006** — android:allowBackup is not set to false in any manifest.<br><sub>Android · Security · Major · effort XS</sub>
- [x] **UI-003** — The muted text token fails WCAG AA.<br><sub>Design system · UI · Critical · effort XS</sub>
- [x] **VEN-010** — No themeMode set, so the app inherits ThemeMode.system and renders an untested dark theme on any tablet in dark mode.<br><sub>Shell · UI · Major · effort XS</sub>

---

## Withdrawn

- [x] **VEN-001** — withdrawn by the auditor: this finding was wrong.
