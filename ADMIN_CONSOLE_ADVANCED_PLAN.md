# Admin console — the next level

What `apps/admin-web/` would need to stand beside a Zomato or Swiggy operations console,
surveyed on 2026-09-05 against `main` at `2ab6a56`.

The two documents before this one are closed. `ADMIN_CONSOLE_FIX_QUEUE.md` (24 findings,
2026-09-01) was about what the console *did wrong*. `ADMIN_CONSOLE_UI_RENOVATION.md`
(2026-09-04) was about what it *looked like*. Neither asked the question this one asks:
**what can the console not do at all.**

**State of the build at this survey.** `tsc -b` clean. `oxlint` exits 0 with no output.
21 routes, 57 source files, 18,771 lines of TSX/TS, of which `src/lib/api.ts` is 1,634 and
`src/ui/primitives.tsx` is 1,082. Every screen is a lazy chunk except the live board.
Next free migration: **0154**.

**The one architectural rule everything below has to respect.** The console reaches the
database through `security definer` RPCs and nothing else — `orders` grants an admin no
read, `restaurants` hides drafts, `menu_items` hides sold-out dishes. Not one item in this
plan is allowed to buy a feature by adding an admin read policy to a table. Where a
proposal appears to need one (live map, realtime board), the item says how it is done
without one.

---

## Part 1 — What exists today

### The 21 screens, by what they are for

| Group | Screen | What it can do today |
|---|---|---|
| Today | Live orders | Open orders, oldest first, **15s poll**, text search, release delivery, cancel order |
| Today | All orders | Full order book, pager, status + date-range filter, unguarded delete with a reason |
| Today | Support | Ticket queue (0095), oldest-first, open/closed filter, resolve with a note, order photos |
| Today | Alerts | `admin_alerts` + rider no-shows (0130), resolve, suspend a rider, jump to Refunds |
| Today | Gift orders | Gift order list, status transitions, line items |
| Today | Platform | 15 stat tiles, a hand-drawn SVG orders/GMV line, top 10 restaurants, 7/30/90 day |
| Catalogue | Restaurants | Roster with derived status pill, publish/unpublish/delist, delete |
| Catalogue | Add restaurant | 8-step wizard: storefront, address+map, hours, legal, bank, team, menu, review |
| Catalogue | Riders | Roster, add/edit, activate, KYC review + override, pay rates, bank, engagement type |
| Catalogue | People | All four populations in one list, role derived, block with a reason (0088) |
| Catalogue | Gift catalogue | Full CRUD on gift shops/items/categories, delivery fee, availability (0118) |
| Reach | Home hero | Slides with scheduling (live/off/scheduled/expired), two-width photos |
| Reach | Map ads | Creatives beside the tracking map (0125), **views + clicks per ad** |
| Reach | Coupons | Platform coupons CRUD; restaurant coupons read-only except an off switch |
| Reach | Broadcast | Push to customers / riders / restaurants, reach preview, send history |
| Money | Refunds | Queue, approve/decline/issue/mark paid, stalled detection (0149) |
| Money | Settlements | Weekly restaurant settlements, adjustments ledger, mark paid, bank last-4 |
| Money | Rider payouts | Payout list, mark paid, rider bank |
| Money | Rider cash | Cash ledger, deposits, per-rider cap |
| Console | Settings | Admin roster, add/remove admin with a password (0153), rider pay rates |

That is a genuinely complete **transactional** console. What it is not yet is an
**operations** console.

### The tables that have no screen at all

Fifty-eight tables exist. The console touches roughly forty. These are written by the
platform every day and read by nobody:

| Table | Written by | Who reads it today |
|---|---|---|
| `admin_actions` | every admin action, append-only (0092) | **nobody** — the console writes the audit trail and cannot show it |
| `reviews` | customers after delivery (0062) | only as an aggregate `rating` column on Top restaurants |
| `service_areas` | hand-written INSERTs | psql |
| `dispatch_settings` | 0148's relay/contest tuning | psql |
| `delivery_surcharge_settings` | night/rain +₹20 (0129) | psql |
| `payment_settings` | the payment gate that ships OFF (0085) | psql |
| `rider_locations` | every rider, continuously | the customer's tracking map |
| `order_messages` | canned chat, both sides (0061) | the two people in the conversation |
| `coupon_redemptions` | every coupon use | nobody — coupons have no ROI view |
| `account_deletions`, `policy_acceptances` | DPDP compliance (0131) | nobody |
| `whatsapp_events` | 0132's confirmations | nobody |
| `rider_cash_policy` | the cap the Cash page enforces | edited per-rider only |

---

## Part 2 — The gap, in one sentence each

What a Zomato/Swiggy city-ops console has that this one does not:

1. **A control tower, not a list.** They open a map with every live order and every rider
   on it. We open a text table that refreshes every 15 seconds.
2. **The system tells you which orders are in trouble.** They surface breaches; we sort by
   age and let a person do the arithmetic.
3. **One page per entity.** An order, a restaurant, a rider each has a 360° page. Here an
   order's facts are split across the live board's modal, All orders, Support, and Refunds.
4. **Search is global.** One box takes an order id, a phone number, an email; ours are
   four separate per-page filters.
5. **The knobs are in the console.** Surge, dispatch timing, service areas and the payment
   gate are all product decisions made in psql here.
6. **Analytics answers "why", not "how many".** We have 15 counters and one line chart.
   They have funnels, cohorts, cancellation reasons and per-partner scorecards.
7. **Not every operator is an owner.** A support agent can read every bank account on the
   platform, because there is exactly one role.
8. **Work leaves the console.** Finance exports nothing; there is no CSV anywhere except
   the menu importer.

---

## Part 3 — The work, in the order it is worth doing

Legend: `[ ]` not started · **Cost** is rough and includes the migration.

---

### Tier 1 — The operations floor

The four items that change what the console *is*. Everything else is an improvement to a
screen; these four are the reason the screens exist.

#### T1-1 — Order 360: one page per order
- [x] **Shipped 2026-09-05** — migration `0154_one_order_on_one_page.sql`,
      `src/orders/OrderDetailPage.tsx`, linked from Live orders, All orders and Support.

**What landed.** `admin_order_detail(order_id)` returns one `jsonb`: the order, its
restaurant and customer, the items with their chosen options, the live delivery, every
dispatch offer, the payment intent, the refunds, the canned conversation, the three
photographs, the review, the complaints, and the `admin_actions` taken on the order *and
on its refunds*. Verified against the live database — largest payload on the platform is
4.8 kB, all 30 orders return without error.

Four decisions worth keeping:

- **Handover attempt counts, never the codes.** An admin who can read the pickup code can
  close a handover that never happened. `handover` carries the attempt counts only, which
  is the diagnostic support actually needs.
- **Audit details are diffed, not dumped.** 0092 stores `{before: <whole row>, after:
  <whole row>}`; one refund moving `approved → processing → paid` is four complete copies
  of a nineteen-column row. `audit_detail_changes()` reduces that to
  `{status: {from, to}}`. The trail keeps everything; the page is told what changed.
- **A deleted id gets a sentence, not a 404.** The id survives in a customer's inbox and in
  a settlement, so `admin_order_detail` raises "Order ZPQ-1020 was deleted by <admin> on
  <date>. Reason given: …" rather than "No such order."
- **The page is read-only.** Every lever already exists elsewhere with an audit row behind
  it. A second Cancel button here would be a second path to one action.

**Known gap, deliberately not closed.** There is no status-transition log in this schema —
`orders.status` is updated in place — so a delivered order does not remember when it was
accepted. Every row on the timeline is a stored timestamp; `ready_by` is labelled as the
promise it is rather than the `accepted_at` it is not. A true per-transition log with an
actor would be a trigger on the busiest table in the system and is a decision of its own.

**Not yet done from the original scope:** the live board's modal, All orders' modal and
Support's photo viewer still exist and were to collapse into this page. Left standing for
now — deleting three working dialogs is its own change.

Today an order's story is scattered. Its timeline is in the live board's modal, its photos
are in Support, its refund is in Refunds, its chat is nowhere, its payment intent is
nowhere, and the audit rows about it are nowhere. Anyone answering "what happened to this
order?" opens three screens and still cannot see the conversation.

One RPC — `admin_order_detail(order_id)` — returning the order, its items with chosen
options, the status transitions with timestamps and actors, the delivery (offers, contest,
rider, OTP events), `order_messages`, `order_photos`, the payment intent and its
verification state, any refund, and the `admin_actions` rows keyed to it. One page that
renders it as a vertical timeline with the money on the right.

Every other screen then links here instead of opening its own modal. This is the single
highest-leverage item in this document, and it also deletes code: the live board's modal,
All orders' modal and Support's photo viewer all collapse into it.

#### T1-2 — Orders at risk: an SLA engine, not a sort order
- [x] **Shipped 2026-09-05** — migration `0155_the_board_says_which_ones_are_in_trouble.sql`,
      `src/orders/LiveOrdersPage.tsx`.

**What landed.** A one-row `sla_settings` table holds the four time thresholds, and
`admin_orders` — dropped and recreated, because `create or replace` cannot add output
columns — now returns `breaches text[]` and `breach_since`. The board leads with the worst
order rather than the oldest, carries a red pill per breach (the reason on hover), counts
them in the header, and has an "In trouble" filter that narrows client-side from rows it
already has.

All six kinds verified against the live database by synthesising each one inside a
transaction and rolling it back — triggers disabled for that transaction only, so nothing
reached a notification, a push or WhatsApp, and the rollback was confirmed afterwards
(order statuses, payment intents, deliveries, thresholds and all fifteen triggers back as
they were).

Two decisions worth keeping:

- **`dispatch_stalled`, not `relay_exhausted`.** Proving exhaustion means reproducing
  0148's candidate query — every online rider already offered and therefore excluded — as a
  second copy that would drift from the first. "Riders were rung, none is holding it, and
  nothing has been offered since" is cheaper, always true when exhaustion is, and is the
  sentence an admin acts on either way.
- **A finished order is never in breach.** What went wrong on a delivered order is a
  question for its own page and for Analytics, not for a board whose job is what somebody
  can still act on.

**The thresholds are a row, not a form, until T2-2.** They are editable with one UPDATE
today; the settings screen that fronts them is Tier 2 work.

The live board sorts oldest-first and says `whereItIs()`. That is a human doing breach
detection by eye. Zomato's floor is a triage list: the system says *which* orders are
late and *why*.

Define breaches in SQL, beside the data, in a `dispatch_settings`-style settings row so
they are tunable without a deploy:

| Breach | Default | The question it answers |
|---|---|---|
| `unaccepted` | placed > 2 min | Is a kitchen asleep? (the ring exists — 0128/0136 — did it work?) |
| `no_rider` | ready_for_pickup > 5 min, no delivery | Did dispatch run out of fleet? |
| `relay_exhausted` | offers relayed to everyone, nobody took it (0148/0150) | Nobody is coming |
| `eta_slipped` | `eta_at` moved past the promise | The customer is about to call |
| `stuck_prep` | preparing > `prep_minutes` + 10 | The kitchen accepted and stopped |
| `payment_unverified` | placed, intent not verified (0085) | Are we cooking for free? |

The board grows a breach filter and a red count in the header; a breach carries its own
"since" clock. This is the screen ops keeps open all day, and it is currently the screen
that asks the most of the person reading it.

#### T1-3 — The board stops polling, without a read policy on `orders`
- [ ] **Cost:** 1 migration + ~60 lines

The 15-second poll is documented as a deliberate trade (`LiveOrdersPage.tsx:24`): Realtime
would need an admin read policy on `orders`, and the console's structural guarantee is that
it reads through named functions only. Both halves of that can be kept.

A trigger on `orders`/`deliveries` broadcasts into a Realtime **broadcast** channel —
`ops:orders` — carrying **no row data at all**, just `{changed: true}`. The console
subscribes to the channel and, on a ping, refetches through `admin_orders` as it does now,
debounced to at most once a second. No table gets a policy, nothing sensitive crosses the
socket, and the board goes from a quarter-minute stale to sub-second. The poll stays as the
fallback when the socket is down, at a much longer interval.

#### T1-4 — Live map: the control tower
- [ ] **Cost:** 1 migration + ~350 lines · **Route:** `/map`

`rider_locations` is written continuously and the console has never drawn it. The customer
app already has the Google basemap and the key handling (Google tiles, key in
`android/local.properties`, free unlimited); the console would need its own browser key,
referrer-restricted.

One RPC — `admin_ops_map()` — returning every on-duty rider's last position, state and
current job, plus every live order's restaurant and drop point. Riders as pucks coloured by
state (idle / offered / carrying / breach), orders as pins coloured by T1-2's breach state,
click either to open its 360 page. A town filter, because `service_areas` says there are
three live towns and a manager works one.

This is what "advanced" looks like from across the room, and it is the screen a founder
demos. It is fourth only because it is worth less than the three above it on a bad day.

---

### Tier 2 — The knobs, brought in from psql

Five product levers currently live in SQL files and a psql session. Each of these is a
small screen over a table that already exists — the cheapest real capability in this
document, and the one that stops requiring an engineer for a business decision.

#### T2-1 — Service areas
- [ ] **Cost:** 1 migration + ~200 lines · **Route:** `/settings/areas`

Where we deliver is data, not code: adding a city is one INSERT and no app release. That
INSERT is still hand-written. Live today: Falna, Ranakpur, Sadri; Ghanerao seeded and
switched off. A table with a switch, a name, a centre and a radius, plus the town-lock rule
from 0126 stated on screen so nobody switches on a town with no kitchen in it.

#### T2-2 — Dispatch tuning
- [ ] **Cost:** ~150 lines · **Route:** `/settings/dispatch`

0148's ring is 15 seconds exclusive, then it relays; two riders reaching for one order are
settled by distance inside a 2-second window; 0150 gives up after the fleet is exhausted.
Those four numbers are the whole feel of the delivery network and none of them is
adjustable without a migration. A form with four fields, a "what this means" paragraph per
field, and an audit row per change.

#### T2-3 — Surge and surcharge
- [ ] **Cost:** ~150 lines · **Route:** `/settings/pricing`

`delivery_surcharge_settings` (0129): +₹20 after 8pm, +₹20 in rain, both riding in
`surge_fee`, riders getting none of it. Ops should be able to switch the rain surcharge off
during a false weather reading without a deploy, and the screen should state the two facts
that are easy to forget — riders are not paid from it, and the weather feed is on a
non-commercial licence.

#### T2-4 — The payment gate
- [ ] **Cost:** ~80 lines · **Route:** `/settings/payments`

0085's trigger ships **off**; one SQL statement arms it. That statement is the difference
between orders being cooked for verified money and cooked on trust. It deserves a switch
with a two-step confirmation, the current state shown in plain words, and — importantly —
a count of unverified live orders beside it so nobody arms it into a queue of orders that
will all fail.

#### T2-5 — Rider cash policy, platform-wide
- [ ] **Cost:** ~60 lines · folded into `/cash`

`rider_cash_policy` is edited one rider at a time from the Cash page. The default cap that
applies to everyone else is invisible. One card at the top of the existing screen.

---

### Tier 3 — Reading what we already write

#### T3-1 — Audit log viewer
- [ ] **Cost:** 1 migration + ~200 lines · **Route:** `/settings/audit`

`admin_actions` has been append-only since 0092 and the console has never shown it. Every
publish, block, refund, cancel, delete and override is in there with the admin's email.
A filterable list — by admin, by action type, by date, by target — plus a link into the
target's 360 page. This is also what makes T4-1's narrower roles auditable rather than
merely restrictive.

Non-obvious: the console reads `admin_actions` only via RPCs and the table is append-only
via triggers. Keep both — this is a read-only screen over a new `admin_list_actions`
function, and it must never grow an export-everything button that turns the audit trail
into a spreadsheet on somebody's laptop.

#### T3-2 — Reviews and ratings moderation
- [ ] **Cost:** 1 migration + ~250 lines · **Route:** `/reviews`

`reviews` is keyed by order and trigger-computes `restaurants.rating` (0062). The console
can see the average and never the sentences. Zomato's console has a review queue for one
reason: a review that names a rider, contains abuse, or is retaliation after a refused
refund has to be removable, and removing it has to recompute the rating.

Nothing on the platform is meaningfully rated yet, which makes every `order by rating` a
coin flip — a moderation screen is also the first place anyone will see whether reviews are
actually arriving.

#### T3-3 — Coupon ROI
- [ ] **Cost:** 1 migration + ~120 lines · folded into `/coupons`

`coupon_redemptions` records every use and nothing reads it. Per code: redemptions, total
discount given, GMV on those orders, new customers vs repeat, and the resulting
discount-to-GMV ratio. Ops currently switches a code off because it *feels* expensive.

#### T3-4 — Compliance queue
- [ ] **Cost:** 1 migration + ~150 lines · **Route:** `/settings/compliance`

`account_deletions` and `policy_acceptances` (0131) exist for DPDP reasons and are
invisible. A deletion request has a legal clock on it. This is small, dull, and the kind of
thing that is only ever built the week before it is needed.

#### T3-5 — WhatsApp and push delivery health
- [ ] **Cost:** ~120 lines · folded into `/broadcast`

`whatsapp_events` (0132) and the broadcast `recipient_count` between them can answer "did
the customer actually get told" — currently the send history says how many were *addressed*,
not how many arrived. Worth doing when the UTILITY template clears Meta, not before.

---

### Tier 4 — The console as a product

#### T4-1 — Scoped roles
- [ ] **Cost:** 1 migration + ~200 lines · touches every RPC's guard

`SettingsPage.tsx:20` states the current position outright: *there is no lesser admin role
and deliberately so — a half-privileged admin who can see bank details but not edit them is
a distinction that sounds useful and protects nothing.*

That argument is correct about *that* split and wrong about the one that matters. The real
split is not read-vs-write on one screen, it is **which screens exist for you**:

| Role | Sees | Does not see |
|---|---|---|
| `owner` | everything, incl. adding admins | — |
| `finance` | settlements, payouts, cash, refunds, bank details | menu, content, riders' documents |
| `support` | live board, orders, tickets, alerts, order 360, refund *requests* | bank accounts, licence numbers, settlements, admin roster |
| `catalogue` | restaurants, menu, gifts, content, coupons | money, people, documents |

A support agent hired next month does not need every restaurant's account number and every
rider's ID document to answer "where is my food". That is not a philosophical distinction;
it is the reason the role exists. Enforced by a sibling of `is_admin()` —
`has_admin_role(role)` — in the database, not in the sidebar. The sidebar hiding a link is
cosmetic; the RPC refusing is the control.

**This is the one item here that needs a decision before it is built**, because it reverses
a decision already written into the code.

#### T4-2 — Global search and a command palette
- [ ] **Cost:** 1 migration + ~250 lines · `Ctrl/Cmd-K`

One `admin_search(q)` that recognises an order id, a phone number, an email, a restaurant
name or a rider name and returns typed hits. Plus the palette's second half: jump to any of
the 21 screens by name. Four per-page search boxes stay; this is the one that works when
you do not know which page the answer is on.

#### T4-3 — Filters in the URL
- [ ] **Cost:** ~150 lines across pages + a small hook

Every filter, page number and search term on every list is component state. A support lead
cannot send a colleague "the stalled refunds for Sadri" — there is no link for it, and a
refresh loses your place. One `useListState` hook syncing to the query string, adopted
screen by screen. This is also the prerequisite for anything resembling saved views.

#### T4-4 — Exports
- [ ] **Cost:** ~120 lines shared

The only CSV in the console is the menu *importer*. Finance reconciles settlements by hand.
One shared "Export CSV" affordance on the list screens that already have RPC-shaped data:
orders, settlements, payouts, cash ledger, refunds, coupon redemptions. Client-side from the
rows already fetched, so it exports exactly what is on screen and needs no new endpoint.

Explicit exception: **not** the audit log (T3-1), and **not** anything carrying a full bank
account number — the RPCs return last-4 only and that stays true of the file.

#### T4-5 — A data layer
- [ ] **Cost:** ~200 lines, no new dependency

Every page hand-rolls `useState(null) + useEffect + useCallback(load)`. Twenty-one copies of
the same six lines, no cache, no dedupe, no stale-while-revalidate, so every navigation
re-fetches from cold and every screen re-implements its own error banner. A single
`useQuery`-shaped hook over the existing `rpc()` — cache by key, revalidate on focus, share
in-flight requests — removes roughly 400 lines and makes navigation instant.

A library (TanStack Query) would do this better and is the obvious suggestion. Rule 4 makes
it an explicit ask, not a convenience: **flagged here, the user chooses.** The hand-rolled
version is ~200 lines and has no upgrade treadmill.

#### T4-6 — Bulk actions
- [ ] **Cost:** ~180 lines

Multi-select on the list screens that have a repetitive action: pause several restaurants
before a storm, resolve a batch of alerts, mark a week of payouts paid, switch off a group
of menu items. Each bulk call is still one RPC per row so the audit trail stays one row per
action — the batching is in the UI, never in the database.

#### T4-7 — Keyboard-first operations
- [ ] **Cost:** ~100 lines

`/` focuses search, `j`/`k` move the selection, `Enter` opens, `Esc` closes, `g` then a
letter jumps to a screen. A dispatcher working a busy evening does not want a mouse. Cheap,
and it compounds with T4-2.

#### T4-8 — An in-console alert bell
- [ ] **Cost:** ~120 lines

Alerts, new tickets and stalled refunds all have queues and none of them announces itself.
Riding on T1-3's broadcast channel: a count in the shell header, a dropdown of the newest
few, a link into the queue. Without T1-3 this would be a fourth poll and is not worth it.

---

### Tier 5 — Analytics that answer "why"

The Platform screen has 15 counters, one line and a top-10. Everything below is a new RPC
plus a section on that screen; none of it needs a new page, and none of it needs a chart
library.

- **T5-1 Funnel.** placed → accepted → picked up → delivered, with the drop at each step.
  Today `orders_rejected` and `orders_cancelled` are two tiles with no denominator.
- **T5-2 Cancellation and rejection reasons.** The reasons are stored; nothing groups them.
  "Kitchen closed" and "item unavailable" are two different problems with two different fixes.
- **T5-3 Restaurant scorecard.** Per partner: acceptance rate, median accept latency, promised
  prep vs actual, rejection rate, refund rate, rating, GMV trend. The Restaurants roster shows
  a status pill and a menu count; this is the number that says whether to keep them.
- **T5-4 Rider scorecard.** On-time %, offer acceptance rate, no-shows (0130), cash exposure
  against the cap, KYC expiry runway, hours on duty. Scattered across three screens today.
- **T5-5 Demand by hour and town.** A 7×24 grid of orders per hour — the single most useful
  picture for deciding rider shifts, and about forty lines of SVG.
- **T5-6 Menu performance.** Items never ordered in 30 days, items that are the reason for an
  order, the effect of the ₹10 platform markup. 685 items exist and nobody knows which ten
  earn the money.
- **T5-7 Repeat rate and cohorts.** New vs returning customers per week. `customers_ordering`
  is one number; whether they came back is the business.

---

## Part 4 — What this plan deliberately does not propose

Written down so it is not re-proposed in six months:

- **No charting library.** `AnalyticsPage.tsx:29` argues the SVG polyline is thirty lines
  and a dependency is an explicit ask. Tier 5 stays within hand-drawn SVG until a chart is
  needed that genuinely cannot be.
- **No admin read policy on `orders`, `restaurants` or `menu_items`.** T1-3 exists
  specifically to get realtime without one.
- **No rollup or summary tables for analytics.** `PlatformStats`' comment holds: at this
  volume, a stored figure is a figure that can be wrong.
- **No self-service anything.** Restaurants are onboarded by admins, forever.
- **No refund path for gifts.** Built in 0115, torn out in 0116; a "gift refund" button is
  a rebuild of a decision already made twice.
- **No second path to an existing action.** `AlertsPage.tsx:34` is right — one action, one
  audit row, however it is reached. Bulk actions (T4-6) obey this.
- **No dark mode.** The console lives on a desk under office lights, and the clean-premium
  rule already fixed the palette.

---

## Part 5 — Suggested order

Nothing here is a dependency chain except where noted, so the order is by value per day of
work.

| Phase | Items | Why here |
|---|---|---|
| **1** | T1-1 Order 360, T1-2 SLA breaches | The two that change daily work. T1-1 also deletes three modals. |
| **2** | T1-3 realtime ping, T4-2 global search, T4-3 URL filters | The console stops feeling like a set of forms. T1-3 unblocks T4-8. |
| **3** | T2-1…T2-5, the knobs | Five small screens, one afternoon each, and psql stops being a business tool. |
| **4** | T3-1 audit viewer, T3-2 reviews, T3-3 coupon ROI | Reading what we already write. |
| **5** | T1-4 live map | Big, visible, and worth more once T1-2 gives the pins a meaning. |
| **6** | T5-1…T5-7 analytics | Each one is an RPC and a section; do them in the order somebody asks a question. |
| **7** | T4-5 data layer, T4-4 exports, T4-6 bulk, T4-7 keyboard, T4-8 bell | Polish that compounds. |
| **later** | T4-1 scoped roles, T3-4 compliance, T3-5 messaging health | T4-1 needs a decision; the other two wait on a hire and on Meta respectively. |

**Migrations:** next free is **0154**. Roughly a dozen of the items above carry one each.

**One open question.** T4-1 reverses a decision written into the Settings screen's own
comment. Everything else in this document extends the console as it is; that item changes
what an admin *is*. Worth answering before Phase 3, because the knob screens are exactly the
ones a support agent should not have.
