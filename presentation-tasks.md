# Zopiqnow — presentation & polish tasks

**Created:** 2026-07-25 · **Status:** research only, nothing built yet.
Four asks, researched against the actual tree and the live project. Each one names
what already exists, what is genuinely missing, and what it costs — including the
things that need a decision from you before a line is written.

Legend: `[x]` done · `[~]` partial · `[ ]` not built · **⚠️** needs your approval first.

**Read this first:** three of the four collide with the version freeze
([[zopiqnow-version-freeze]] — no new dependency, SDK bump, or tool change without an
explicit approved upgrade task). Every collision is flagged **⚠️** with a
no-new-dependency alternative beside it wherever one exists. P3 and P4 both have one.
P1 does not, entirely.

---

## What the codebase already has (audited 2026-07-25)

Worth stating up front so nothing below gets rebuilt.

| Thing | Where | State |
|---|---|---|
| Push, end to end | `send-notification` edge fn, `push_on_notification_insert` trigger, 4 device tokens | ✅ live since B0 |
| Notification fan-out | migration 0047, five triggers | ✅ live |
| Customer order status stream | `order_supabase_datasource.dart` `.stream()` on `orders` | ✅ live |
| Delivery states incl. arrivals | migration 0049 — `arrived_at_restaurant`, `arrived_at_customer` | ✅ live |
| iOS 120 Hz ProMotion | `CADisableMinimumFrameDurationOnPhone` = true, `Info.plist:5` | ✅ **already done** |
| Impeller on Android | Flutter 3.44.5 default | ✅ |
| Cloudinary upload from the console | `apps/admin-web/src/lib/uploads.ts` | ✅ images only |
| Admin console CRUD pattern | `apps/admin-web/src/restaurants/`, `riders/`, `menu/` | ✅ copy this |
| Hero carousel | `apps/customer/lib/features/home/presentation/widgets/home_hero_carousel.dart` | ✅ **slides are rows** (0053); the in-Dart art is now the empty state |
| Hero slides table + console | migration 0053, `apps/admin-web/src/content/HeroSlidesPage.tsx` | ✅ built 2026-07-26 |
| High refresh rate, Android | `apps/customer/android/.../MainActivity.kt` | ✅ built 2026-07-26, customer only |
| Hero motion loops | migration 0054, `motion_url`, `uploadMotion()`, `_SlideMotion` | ✅ built 2026-07-27, no new dependency |

Pinned versions this work has to live inside: Flutter **3.44.5**, Dart SDK `^3.12.2`,
`compileSdk 36`, `targetSdk 35`, `minSdk 24`, iOS deployment target **13.0**,
`firebase_messaging 15.1.6`, `flutter_local_notifications 18.0.1`. Next free migration
is **0055** (0052 is the live order card, 0053 the hero slides, 0054 the hero motion loop).

---

## P1 — Live order notifications (the Swiggy lock-screen card)

The reference screenshots are **iOS Live Activities** (ActivityKit). But look at what is
actually on screen: a headline, a progress bar, an icon on the right, and it stays put.
**Every one of those is a standard Android notification**, available on the Android 10
floor, with no new dependency and no `targetSdk` bump.

Verified in the pinned package — `flutter_local_notifications 18.0.1` exposes
`showProgress`, `maxProgress`, `progress`, `largeIcon`, `ongoing`, `onlyAlertOnce`,
`subText` and `colorized`
(`notification_details.dart:117–398`). That is the whole screenshot.

### What each platform tier actually buys

| Tier | What it adds over the one below | Availability | Reachable today? |
|---|---|---|---|
| **Android, any version** | The screenshot: headline, progress bar, large icon, persistent, on the lock screen | API 24+ | ✅ **built (Tier 1)** |
| **Segmented tracker, any version** | **Segments and milestone points** — the tracker with a moving marker, not a plain bar — painted onto a `Canvas` and used as the notification body | API 24+ | ✅ **built (Tier 2)**, no dependency |
| **Android 16 Live Updates** | What is left once the tracker is reproduced: the status-bar **chip** while the phone is in use, and the **guarantee** of promoted placement at the top of the lock screen and AOD | API 36 | ✅ **built (Tier 2)**, runtime-gated · chip on a `targetSdk 35` app is unverified |
| **iOS Live Activities** | Dynamic Island · the iOS presentation in the screenshots | iOS 16.1+ · 17.2+ for remote *start* | ❌ deployment target is **13.0** |

**The honest summary:** the *look* is now identical on every Android from the version 10
floor up — Tier 2 paints the segmented tracker itself rather than waiting for API 36 to
draw one. What remains genuinely exclusive to Android 16 is the **placement**: the chip
in the status bar, and the guarantee of the top slot on the lock screen rather than
wherever the shade puts it. Those two are drawn by system UI. There is no backport, no
support library, and no trick — they are the one part of this feature that a phone's
Android version decides and code does not.

Below Android 16 an ongoing notification competes for lock-screen position like any
other. In practice it sits high, because it is ongoing and recently updated, but nothing
guarantees it. That is the real gap, and it is worth naming honestly rather than
discovering on a device.

### The three-tier plan

- [x] **Tier 1 — the card itself. Android 10 → latest, no new dependency** — *built
      2026-07-25. Migration 0052, `send-notification`, `order_live_card.dart`. Not yet
      run on a device: see the manual steps below.*
  - [x] One persistent notification per live order, updated in place by reusing the same
    notification id — FNV-1a over the order id, because the card is drawn in the FCM
    background isolate as often as the app's own and `String.hashCode` promises nothing
    across that boundary
  - [x] `showProgress: true` with `maxProgress: 100`. **The ladder is computed from
    `orders.status` and `deliveries.state` together, not from whichever moved last** —
    a rider reaches the counter (65) before the kitchen packs the bag (55), so a bar
    driven by one table alone walks backwards on screen. `order_live_payload` takes the
    furthest point either has reached. Verified against a real order:
    20 → 35 → 65 → 75 → 95 → 100, with the out-of-order `ready_for_pickup` correctly
    *not* moving it back
  - [~] `largeIcon` — **the launcher mark, not per-state art.** There is no cooking /
    rider / at-the-door illustration in the repo and inventing brand art is not this
    task's job. It also cannot be a Flutter asset: `largeIcon` needs an Android
    *drawable*, so the art must land in `android/app/src/main/res/drawable/`. Dropping
    three files there and switching on `stage` is the whole remaining change
  - [x] Headline per state, from `order_live_payload`: "Preparing your order",
    "Delivery partner is at the restaurant", "Your delivery partner is outside"
  - [x] `subText` carries "Arriving in N min" — but counted down against a fixed
    `eta_at` the server sends, **not** a minutes-remaining number computed when the push
    was built. A deadline that never moves is what makes Rule 3 structural rather than
    hoped for
  - [x] `ongoing: true`, `onlyAlertOnce: true`, dedicated `order_live` channel at
    `IMPORTANCE_DEFAULT` with sound and vibration off **on the channel itself**, so it
    reads as the silent tracker it is in system settings
  - [x] `colorized: true` with the Swiggy-orange brand token, per [[zopiqnow-swiggy-design]]
  - [x] Tap → `/orders/:id`. `PushService` parks the order id and `ZopiqApp` drains it,
    which is what makes a tap that woke the app *from dead* still land on the tracking
    screen. Ordinary alerting pushes got the same treatment — they had no tap
    destination before today
  - [x] Cancel on `delivered` / `cancelled` / `rejected` — the terminal stages post a
    tick of their own so there is always an event that takes the card down
  - [x] **Verified available in the pinned `flutter_local_notifications 18.0.1`** — no
    new dependency, no `targetSdk` bump, no version-freeze collision

- [x] **Tier 2 — the segmented tracker, on every Android** — *built 2026-07-25.
      `packages/zopiq_live_card/`. Not yet run on a device: see the manual steps below.*

  Asked for as "Android 16 Live Updates", built as "the segmented tracker on all Android
  versions, and the Android 16 treatment where the OS offers it". The split below is not a
  preference — the platform forces it, and the reason is worth reading once.

  **What Android 16 alone can do, and no amount of code changes it:** the status-bar
  **chip** while the phone is in use, and the **guarantee** of the top slot on the lock
  screen and AOD. Both are drawn by system UI. There is no support-library backport and
  no trick; below API 36 an ongoing notification competes for position like any other.

  **What was reachable everywhere, and now is:** the **segmented tracker with milestone
  points**. Tier 1 shipped a plain unbroken bar because that is the only shape
  `flutter_local_notifications` exposes. It is now painted onto a `Canvas` and handed to
  the notification as a custom body, so an Android 10 phone shows the same tracker an
  Android 16 phone does.

  - [x] **`packages/zopiq_live_card/`** — an in-repo, Android-only Flutter plugin, written
    in Java against the framework `Notification.Builder`. **Zero new dependencies**: no
    package bump, no androidx artifact, no Kotlin stdlib, no AGP pin — `pubspec.lock` is
    byte-identical after the change. Verified with `git diff pubspec.lock` (empty)
  - [x] **A package rather than Kotlin in `apps/customer/android/app`, and this is the
    load-bearing decision.** The card is drawn from the FCM background isolate, which runs
    in a `FlutterEngine` that `firebase_messaging` constructs itself and populates from
    `GeneratedPluginRegistrant`. Only real plugin packages land in that file. Kotlin in the
    app module would have answered the channel with the app foregrounded and gone silent
    with it killed — which is the entire situation the live card exists for. Confirmed
    after the build: `GeneratedPluginRegistrant.java:89` now registers it
  - [x] **API 36+ → `Notification.ProgressStyle`** with three segments and two milestone
    points (`PromotedStyle.java`), plus the `android.requestPromotedOngoing` extra and
    `POST_PROMOTED_NOTIFICATIONS` in the plugin's manifest — confirmed merged into the
    app's packaged manifest. That is the chip and the promoted placement
  - [x] **API 24–35 → `DecoratedCustomViewStyle`** over a hand-painted bar
    (`TrackerBar.java`). The decorated style keeps the system's own header — icon, app
    name, "Arriving in 18 min", the expander — and replaces only the body, which is what
    lets a custom layout inherit the shade's light or dark theme instead of guessing at it
  - [x] **The two branches are mutually exclusive by Google's rules, not by taste.** A
    promoted notification may not carry custom `RemoteViews`, and may not be colorized.
    So the Android 16 path cannot use the painted bar, the older path cannot be promoted,
    and `setColorized` is gone from both — it was doing nothing anyway, since the platform
    honours it only for foreground-service and media notifications. `setColor` still tints
  - [x] **One ladder, one place.** `Ladder.java` holds the milestones (35 / 75 / 100) and
    both branches read them, so the painted bar and the platform's own tracker cannot
    drift into showing different steps. Three milestones, not eight: `accepted`,
    `claimed`, `packed`, `rider_at_restaurant` and `at_door` all move the bar without
    earning a dot, which is what stops it reading as a progress bar with a rash
  - [x] **Taps survive the move.** The card is no longer drawn by
    `flutter_local_notifications`, so its taps no longer arrive through `_onLocalTap`. The
    plugin builds its own `PendingIntent` and hands the order id back two ways — a live
    callback for an app that is running, and a parked value for a tap that started the
    process from dead, because a cold start has no Dart alive to call back
  - [x] **The bitmap is clamped to 720px wide.** It crosses to `system_server` through a
    Binder transaction with about a megabyte to spend, and it is sent twice — collapsed
    and expanded. Unclamped it would be 960px on a density-3 phone
  - [x] Degrades silently downward, per Rule 5. Same notification id, same `order_live`
    channel as Tier 1, so a phone that updates from 15 to 16 upgrades its own live card
    mid-order without the server knowing
  - [x] Migration 0052 and `send-notification` are **untouched**. This is a device-side
    change end to end; the payload it reads is the one Tier 1 already defined
  - [ ] **The one open question — `targetSdk`.** Google documents the promotion
    requirements as properties of the notification plus the permission, and says nothing
    about `targetSdk 36`. The code is compiled against `compileSdk 36` (already the app's
    value) and gated at runtime on `SDK_INT >= 36`, so **nothing here needed the freeze
    broken**. But whether the OS actually honours promotion for a `targetSdk 35` app is
    unverified and only an Android 16 device can answer it. If the chip does not appear,
    that — and only that — is what the `35 → 36` bump ⚠️ would buy, and it stays its own
    approved task rather than being folded in here

- [ ] (skip for now)  **Tier 3 — iOS Live Activities** ⚠️ **largest single item in this file**
  - **Bump iOS deployment target 13.0 → 16.1** (or gate: Live Activity on 16.1+, plain
    push below). Dropping iOS 13/14/15 is a product decision, not a technical one
  - A **Widget Extension target in Swift** — ActivityKit UI cannot be written in Dart.
    This is a new Xcode target, a new build config, and Swift code in a repo that has
    none. It is the reason this tier is not a week
  - A `MethodChannel` so Dart can `start` / `update` / `end` the activity locally
  - Remote updates: FCM HTTP v1 **does** support Live Activity payloads
    ([Firebase docs](https://firebase.google.com/docs/cloud-messaging/ios/live-activity)),
    but each activity has **its own push token**, separate from the FCM registration
    token, and both it and the push-to-start token rotate. That means a new
    `live_activity_tokens` table and token-refresh observers — `device_tokens` will not do
  - `send-notification` grows an `apns` branch with `apns-push-type: liveactivity`
  - **iOS is unproven on this project.** Only `apps/customer/ios` exists (vendor and
    rider are Android-only), and there is no evidence in the repo of an iOS build ever
    having been run, signed, or shipped. Confirm the app builds and runs on a device
    before costing this tier at all

### Server-side work, common to all three tiers

- [x] **Migration 0052 — narrate the states the customer currently isn't told about.**
      Done. `order_live` is a second, silent stream over the same table: a row per step
      including the two 0047 skips, stamped `read_at` at insert so it can never reach
      the unread badge, and filtered out of the inbox list as well. The five
      `order_update` rows still buzz, exactly as before — one noisy channel, one silent
- [x] Rider arrival events (`arrived_at_restaurant`, `arrived_at_customer`) now fire.
      A trigger on `deliveries.state`, so it does not care which RPC moved the row
- [x] Payload carries `order_id`, `stage`, `progress`, `eta_at`, `title`, `body` so the
      device redraws without a round trip. **Not `orders.status`** — it reads
      "preparing" while the rider is at the counter, and a second field that disagrees
      with the first is one somebody eventually believes
- [x] `send-notification` routes `order_live` to a data-only push — no `notification`
      block, which is what stops Android drawing a tray entry beside the card.
      Verified: FCM accepted and delivered one (`{"devices":1,"sent":1}`)
- [x] **The writer refuses to repeat itself.** Because progress is the furthest point
      either ladder reached, an event can leave the card byte-identical — the kitchen
      packing a bag after the rider already arrived is the ordinary case. Sending it
      would wake every device to redraw nothing, so the previous tick is compared and a
      duplicate dropped. This cut the walk-through from 7 pushes to 6

### Verifying Tiers 1 and 2 on a device ([[zopiqnow-no-test-files]] — manual, by hand)

What is already proven, server-side, without a phone: the ladder is monotonic across an
out-of-order arrival, the duplicate tick is dropped, a cancellation posts a terminal
tick, `order_live` rows never reach the unread badge, and FCM accepts and delivers the
data-only push.

What Tier 2 additionally proved without a phone, at build time: the module compiles
against `compileSdk 36` (so `ProgressStyle`, its segments and its points are the real
API and not a guess), `pubspec.lock` is unchanged, and — the one that mattered —
`GeneratedPluginRegistrant.java` registers the plugin, which is what lets the FCM
background isolate reach it with the app killed. The permission merged into the packaged
manifest.

What is **not** proven is anything that happens on a screen.

1. `flutter run` the customer app on a real device, signed in, and confirm a token
   registers (`select * from device_tokens where audience='customer'`).
2. Place an order. Walk it through the vendor and rider apps: accept → start cooking →
   rider claims → **rider taps "I've arrived" before the kitchen marks it packed** (this
   is the case the ladder exists for) → packed → pickup → arrived → delivered.
3. Watch for, at each step: **one** card, not a stack; the bar moving forward and never
   back; no sound or vibration after the first `order_update` buzz; "Arriving in N min"
   counting down.
4. **Tier 2, collapsed and expanded.** The tracker must show **two gaps** and **three
   dots**, the dots filling as the order passes 35 / 75 / 100. Expand the card: the same
   tracker plus the line of prose. Then check the two things a hand-painted bitmap can
   get wrong and nothing else can — **switch the phone between light and dark theme**
   (the gaps must show the shade's background through them, not a grey stripe), and check
   the bar is not **clipped or stretched** at either end.
5. **Lock the phone and repeat from step 2.** The card is drawn in the FCM background
   isolate — this is the path that actually matters, the only one the emulator lies
   about, and since Tier 2 it is also the path that proves the plugin is reachable from
   an engine the app did not create. If the card appears foregrounded but not from the
   lock screen, that is the failure this whole package was shaped to avoid.
6. Tap the card. It must open `/orders/<id>` and **not** dismiss itself. Then **force-stop
   the app, place a new order and tap that card** — the cold-start path hands the order id
   back a different way than the warm one, so it is a separate thing to get wrong.
7. On `delivered`, the card must vanish. Repeat for a customer cancellation.
8. Repeat the whole thing on the **Android 10 floor** ([[zopiqnow-android-compat]]).
   Android 10 is where the painted tracker either holds up or does not.
9. **On an Android 16 device, if one is to hand:** the card should look different, because
   system UI is drawing the tracker rather than the app. Look for the **chip in the status
   bar** while using the phone. If it is absent, that is the `targetSdk 35 → 36` question
   above answering itself — everything else on the card should still be correct.

Known ceiling, worth confirming rather than discovering later: a data-only push reaches a
dozing phone at high priority but Android may still hold it, and a **force-stopped** app
receives nothing at all until it is next opened. That is the same for every sender and
nothing in this slice can raise it — it is the honest floor below Android 16.

### Rules for this slice

1. **One notification per order, updated in place.** A stack of six is the failure mode.
2. **Silent after the first.** `setOnlyAlertOnce`, and `order_live` never vibrates.
3. **The ETA must never move backwards without a reason on screen** — the B3 rule, and it
   binds harder here because this number is on the lock screen.
4. **It must vanish.** A live notification surviving a delivered order is worse than
   never having shown one.
5. Tiers degrade downward silently. A device that cannot do the rich card gets the plain
   one and is told nothing about what it is missing.

---

## P2 — Admin CRUD for the customer home hero

Today `home_hero_carousel.dart` is **1111 lines** with the slides written into Dart:
copy, colours, and artwork composed in-app (gradients, rotating ray bursts, a sheen).
Its own doc comment calls the art *"a temporary in-app composition until brand art is
supplied"* — so this was always the plan.

There is **no banner, promo, hero, or campaign table** anywhere in `supabase/migrations/`.
This is greenfield.

**Built 2026-07-26.** Migration 0053 applied and verified against the live database;
console module and customer wiring land with it. The one thing not proven is the same
thing P1 has outstanding — nothing that happens on a phone screen. Manual steps below.

- [x] **Migration 0053 — `hero_slides`** — *applied.*
  - [x] `id`, `title`, `subtitle`, `cta_label`, `cta_target` (deep link or restaurant id),
    `image_url`, `sort_order`, `is_active`, `starts_at`, `ends_at`, `created_at`
  - [x] **RLS:** public `select` for `anon` + `authenticated` where
    `is_active and now() between starts_at and coalesce(ends_at, 'infinity')` —
    a scheduled-but-unpublished slide must not be readable, not merely unrendered.
    Verified: four rows (live / off / scheduled next week / expired yesterday), and
    `set role anon` reads exactly one
  - [x] Writes via `admin_*` RPCs behind `assert_admin()`, matching the pattern every other
    admin surface uses (0026–0038). **No table-level write grant** — and this turned out
    to need saying out loud in SQL. Supabase's default privileges grant ALL on every new
    table in `public` to `anon` and `authenticated`, so a fresh table arrives *writable*
    and the only thing refusing an insert is the absence of an insert policy. The insert,
    update and delete are now revoked explicitly, so the refusal does not depend on a
    policy nobody has added yet
  - [x] `revoke all on function ... from public, anon, authenticated` on every new RPC —
    the 0045 lesson. `assert_hero_cta` is revoked from all three: it is called only by
    the RPCs, in their own definer context
  - [x] Verified as a real admin (`request.jwt.claims`): create → the slide is invisible
    to a customer → publish → visible → edit → **still published, and editing does not
    publish** → delete. A non-admin gets "You are not a Zopiqnow admin."
- [x] **Console module `apps/admin-web/src/content/HeroSlidesPage.tsx`**
  - [x] Copies the shape of `riders/RidersPage.tsx` (one form for add and edit, actions on
    the row); reuses `lib/uploads.ts` `uploadPhoto()` **unchanged**
  - [x] List, create, edit, reorder (an integer `Position` field — a field, as the cheaper
    of the two), publish/switch off, schedule, delete
  - [x] **Live preview at the phone's real aspect ratio** — 393pt wide to scale, with the
    real numbers read off `home_app_bar.dart` (`headerInset` 158, `promoHeight` 238,
    42.4pt headline). It draws the **floating location row and search pill over the art**,
    because those are what cover the top third of every upload — a preview that omitted
    them would be the crop nobody ships against
  - [x] Route in `App.tsx`, "Home hero" in the sidebar
  - [x] `datetime-local` is converted through the admin's own timezone in both directions.
    A bare local string handed to Postgres reads as UTC, which is how an IST admin
    schedules 9am and publishes at 2:30pm
- [x] **Customer app**
  - [x] `features/home/data/datasources/hero_slide_datasource.dart` + `heroSlidesProvider`
    (in `home_providers.dart`, beside the rest). Filed under `data/datasources/` rather
    than the `data/hero_datasource.dart` written above, to sit where the other four do
  - [x] `HomeHeroCarousel` takes `List<HeroSlide>`; `_PublishedSlideView` draws the
    uploaded art with a scrim under the copy — **not** the ray bursts and sheen, which
    exist because there was no artwork and fight a real photograph
  - [x] **The existing in-Dart art is the empty state.** No campaign, a failed fetch and
    an offline phone are one case: `valueOrNull ?? const []`, and the carousel draws what
    ships today. The hero never shows a spinner or an error about a marketing banner
  - [x] Motion budget kept: the published slide reuses the same entrance lift and swipe
    parallax and adds no loop of its own beyond the CTA breath, all off under
    reduce-motion. One `PageView` for both kinds, because rebuilding it would attach two
    views to one `PageController`
  - [x] Two things the variable slide count exposed, both now handled: the auto-advance is
    **off for a single slide** (nowhere to advance to), and the page dots showed a fixed
    five-dot sliding window regardless of `count` — they now show exactly `count` dots up
    to five, and nothing at all for one slide
  - [x] `cta_target` navigation: `/restaurant/<id>` is **pushed** so Back returns Home; a
    tab path is `go`, because pushing a bottom-nav tab over Home leaves the nav bar
    highlighting a tab the user is not on
- [x] Cache: `heroSlidesProvider` is not `autoDispose`, so it is fetched once per process
      and not once per Home build, and Home's pull-to-refresh invalidates it — the gesture
      a person already makes when they expect the screen to be newer than it is. The
      invalidation is deliberately not awaited: the spinner belongs to the feed

### Verifying P2 on a device ([[zopiqnow-no-test-files]] — manual, by hand)

Proven without a phone: the read policy hides off / scheduled / expired slides from
`anon`; the admin loop creates, publishes, edits without republishing, and deletes; a
non-admin is refused; a non-Cloudinary image, an empty headline, an end before its start,
an unlisted restaurant and an arbitrary URL are each refused with a sentence; and the
customer app's **exact PostgREST query** returns the live slides in position order with
the switched-off one absent (checked with the anon key over HTTPS, then cleaned up).

1. Console → **Home hero** → Add slide. Upload art and watch the preview: the headline
   must not collide with the floating search pill.
2. Save. It appears **Off**. Open the customer app — the hero is still the shipped
   artwork, six slides, unchanged. That is rule 1, and it is the whole safety property.
3. **Publish** it. Pull to refresh Home. One slide, your art, your copy, one dot's worth
   of carousel — no dots at all, and no auto-advance, because there is one slide.
4. Add a second and publish it. Now: two dots, auto-advance every five seconds, swipe
   both ways, and the copy drifts as you swipe.
5. Tap the CTA on a slide with **no** target — Home scrolls to the restaurant list, arrow
   pointing down. Then one pointing at `/restaurant/<id>` — the menu opens, arrow pointing
   forward, and **Back returns to Home**.
6. Switch both off. Refresh. The shipped artwork is back, with no blank frame in between.
7. Schedule one for five minutes out. It must be **absent** until then, not present and
   hidden — check by refreshing at four minutes and at six.
8. Turn on **reduce motion** in the OS: no auto-advance, no CTA breath, swiping still
   works.
9. Kill the network and cold-start: the shipped artwork, no error, no spinner in the hero.
10. Repeat on the **Android 10 floor** ([[zopiqnow-android-compat]]) — a full-bleed
    Cloudinary JPEG decoded at hero size is the new cost on the first screen.

### Rules

1. **The empty state is the current design.** No content, no regression.
2. Slide art is Cloudinary-hosted ([[zopiqnow-cloudinary-images]]), never bundled.
3. An expired or deactivated slide disappears from the *query*, not from a client filter.
4. `cta_target` is validated server-side against something that exists — a hero pointing
   at a delisted restaurant is a dead end on the most prominent surface in the app.

---

## P3 — Run at the device's maximum refresh rate

The smallest item here, and half of it was already done.

**Built 2026-07-26.** 34 lines of Kotlin in one file, no new dependency, and it compiles —
`flutter build apk --debug` succeeded against the pinned SDK. The one thing not proven is
the one thing only a 90/120 Hz phone can prove: the frame rate on screen. Manual steps below.

- [x] **iOS** — `CADisableMinimumFrameDurationOnPhone` is already `true`
      (`apps/customer/ios/Runner/Info.plist:5`). ProMotion 120 Hz is enabled. **Nothing to do.**
- [x] **Impeller** — default on Android in Flutter 3.44.5.
- [x] **Android** — was a bare `class MainActivity : FlutterActivity()`. Nothing requested a
      high-refresh display mode, so on a 90/120 Hz phone whose system default mode is 60 Hz,
      the app rendered at 60. It now asks.

Two ways to fix it:

| Approach | Cost | Verdict |
|---|---|---|
| **Kotlin in `MainActivity`** — enumerate `display.supportedModes`, pick the highest `refreshRate` at the current resolution, set `window.attributes.preferredDisplayModeId`. API 23+, ~20 lines | **no new dependency** | ✅ **built** |
| `flutter_displaymode` package — `FlutterDisplayMode.setHighRefreshRate()` | a new pub dependency | ⚠️ not taken — it does exactly the above and would collide with the freeze for no gain |

- [x] Implement the Kotlin route in `apps/customer/android/.../MainActivity.kt` —
      `preferredDisplayModeId` is API **23+**, so this reaches the Android 10 floor and
      everything below it down to `minSdk 24`. No `targetSdk` bump, no lockfile diff
- [x] **Match the resolution.** Naively picking the highest-refresh mode can also switch
      resolution and blur the display — a 120 Hz mode is frequently offered only at 1080p on
      a 1440p panel. The modes are filtered to the *current* `physicalWidth`/`physicalHeight`
      first, and the max refresh rate taken from what is left, so sharpness is never traded
      for smoothness
- [x] **Don't re-request the mode you are already in.** A 60 Hz panel reports 59.94, so the
      comparison carries a 1 Hz margin. Without it, a 60 Hz-only phone would hand the
      compositor a mode change that changes nothing on every cold start
- [x] `Display` is read two ways: `Activity.getDisplay()` on API 30+, and the deprecated
      `WindowManager.getDefaultDisplay()` below it, which is the correct route there
- [x] **`Surface.setFrameRate()` (API 30+) — considered, deliberately not used.** It needs the
      surface Flutter renders into, and `FlutterActivity` does not expose it; reaching into
      `FlutterView`'s internals to find it would be a fragile way to say the same thing the
      mode request already says, on a subset of the devices
- [x] **Customer only — decided 2026-07-26, not overlooked.** The vendor app is a kitchen
      tablet where nobody is watching an animation, and the rider app runs a whole shift on
      GPS, where battery is the scarce thing and 120 Hz spends it. Their `MainActivity`s stay
      bare on purpose. If the rider app later grows a map that pans, revisit it there and only
      there
- [ ] **Verify with numbers, not vibes.** `flutter run --profile` plus the performance
      overlay on a 90/120 Hz device. A high-refresh app that drops to 45 fps is *worse*
      than a steady 60 — raising the ceiling raises the cost of every dropped frame
- [ ] Re-check the Android 10 floor after the change ([[zopiqnow-android-compat]])

### Verifying P3 on a device ([[zopiqnow-no-test-files]] — manual, by hand)

Proven without a phone: it compiles against the pinned Flutter 3.44.5 / `compileSdk 36`, and
`pubspec.lock` is untouched. Nothing else about this task can be proven off-device — the
whole feature is a number the compositor chooses.

1. On a **90 or 120 Hz** phone, set the system display setting to its *standard* / 60 Hz
   mode if it has one — that is the case this change exists for. `flutter run --profile`.
2. Turn on the performance overlay. The raster and UI graphs should now show a **~8.3 ms
   (120 Hz) or ~11.1 ms (90 Hz)** frame budget rather than 16.7 ms. If the budget line has
   not moved, the mode request was refused and nothing else below matters.
3. Scroll the home feed hard. **Both graphs must stay under the new line.** A 120 Hz app that
   drops to 45 fps is worse than a steady 60 — if the feed cannot hold it, cap it deliberately
   (see the rule below) rather than shipping judder.
4. Check the **display resolution did not change**: text must be exactly as sharp as before.
   That is the filter in step one of the Kotlin doing its job, and a blurry screen is the
   failure mode it exists to prevent.
5. On a **60 Hz-only phone**, confirm nothing regressed — no flicker on launch, no mode
   renegotiation. The 1 Hz margin should mean the request is never made at all.
6. Repeat on the **Android 10 floor** ([[zopiqnow-android-compat]]).

### Rule

Higher refresh rate is only a win if the frame budget is met. If profiling shows the
home feed cannot hold 120 fps, cap it deliberately rather than shipping judder.

---

## P4 — Admin-uploaded looping video in the hero

Depends on **P2**, which is now built — same table, same console module, same carousel, so
this is a `motion_url` column beside `image_url` rather than a feature from scratch.

### The dependency question, which has a good answer

The obvious route is the `video_player` package. It is **not** in `apps/customer/pubspec.yaml`
and adding it is a version-freeze item ⚠️. It also brings ExoPlayer/AVPlayer weight, a
controller lifecycle per slide, and an autoplay-in-a-carousel problem.

**There is a route with no new dependency at all:** Flutter's built-in `Image` decodes
and loops **animated WebP and GIF** natively, and Cloudinary transcodes an uploaded MP4
into animated WebP on delivery (`f_webp,fl_animated`, plus `w_`/`q_auto` to bound it).
The admin uploads an MP4; the phone receives a looping animated WebP through the
`Image.network` path `ZopiqNetworkImage` already uses.

| | Animated WebP via Cloudinary | `video_player` |
|---|---|---|
| New dependency | **none** | ⚠️ yes |
| Audio | no | yes |
| Length that stays sane | 3–8 s | any |
| Loops | native | native |
| Per-slide controller lifecycle | none | yes |
| Memory | whole animation decoded in RAM | streamed |

A hero loop is silent, short, and decorative. **Recommend animated WebP.** Revisit
`video_player` only if you later want sound or a clip over ~10 seconds.

**Built 2026-07-27.** Migration 0054 applied and verified against the live database;
console upload path and customer wiring land with it. `pubspec.lock` is unchanged, so the
freeze held. The one thing not proven is the same thing P1, P2 and P3 have outstanding —
nothing that happens on a phone screen. Manual steps below.

- [x] **Decided: animated WebP, no new dependency** — confirmed 2026-07-27. Everything
      below is built on it
- [x] `hero_slides` grows `motion_url` (nullable) beside `image_url`, and the still stays
      **required** — it is the poster, the reduce-motion fallback, and what shows while
      the loop downloads. There is deliberately no "a slide with a loop must also have a
      still" check: the still is required of *every* slide already, so rule 1 holds by
      construction rather than by a second rule that could drift out of step with the first
- [x] **`uploads.ts` grew a video path.** `uploadMotion()` posts to Cloudinary's
      `/video/upload` with the same unsigned preset, caps the *source* at 100 MB, then
      builds the delivery URL and **fetches it to measure what it actually weighs**
- [x] **The column stores the derived WebP URL, not the uploaded MP4.** So the size an
      admin is shown before saving is the size a customer downloads — the same bytes from
      the same URL — rather than an estimate of it. It also keeps Cloudinary's grammar out
      of the phone: `motion_url` is a URL to an image, exactly like `image_url`
- [x] Console: upload the MP4, **the transcoded loop plays in the same live preview** (an
      animated WebP plays in an `<img>`, so what the admin watches is the file the phone
      decodes), and the delivered size is stated — green under the target, amber over it
- [x] Carousel: still first, loop faded in over it when decoded. Never a blank frame,
      because the still is never removed — the loop is a layer above it, not a replacement
- [x] **Only the visible slide animates**, via `TickerMode`. Flutter pauses multi-frame
      images when the ticker mode is off, which parks an off-screen loop *without* tearing
      it down — so swiping back resumes it instead of paying to decode it again. The
      `< 0.5` page test means exactly one loop runs at any moment (rule 3)
- [x] **Respect reduce-motion** — and by *not mounting the loop at all*, which is the
      more expensive of the two options and the right one. Flutter already pauses animated
      images under `disableAnimations`, but a paused animation is frozen on its own first
      frame: an arbitrary video still, not the artwork the admin composed the headline
      against. Rule 1 says every failure path lands on the still, so this one does
- [~] **Low battery / data saver — considered, not built.** Both need a plugin
      (`battery_plus`, `connectivity_plus`); neither is in `pubspec.yaml` and adding one
      is a freeze item ⚠️ for a decorative loop already bounded to ~1 MB and already
      paused whenever it is off-screen. Filed here rather than done, and it is the one
      unchecked box in this slice
- [x] Budget and enforce a cap — **≤ 1.5 MB target, 4 MB hard refusal.** Over the target
      the console says the number in amber and still lets an admin ship it deliberately;
      over the cap `uploadMotion()` refuses and the slide never reaches the database
- [ ] Profile on the **Android 10 floor** specifically. Animated WebP decode is not free,
      and the hero is the first thing on the first screen

### The transformation, and the flag that silently breaks it

`f_webp,fl_animated,fl_awebp,w_720,q_auto:eco,du_8,fps_12`

Measured against `demo/video/upload/dog` on 2026-07-27, because guessing at this was the
part most likely to ship wrong:

| Transformation | Delivered |
|---|---|
| `f_webp,fl_animated,fl_awebp,w_720,q_auto:eco,du_8,fps_12` | **1,137,876 B** |
| `f_webp,fl_animated,fl_awebp,w_800,q_auto:eco,du_6` | 2,458,744 B |
| `f_webp,fl_animated,fl_awebp,w_800,q_auto:low,du_6` | 2,163,538 B |
| `f_webp,fl_animated,w_400` | 7,000 B |
| `f_auto:animated,w_400` | 7,000 B |

Two things worth reading off that table.

**`fl_awebp` is load-bearing, and its absence is silent.** The last two rows answer with
HTTP 200 and `Content-Type: image/webp` — and a **single still frame**. A slide built that
way shows a motionless picture on top of a motionless picture: it looks entirely correct
and does not move, with nothing on screen or in a log to say why. `assert_hero_motion`
refuses a URL without the flag for exactly that reason. Note also that the obvious modern
route, `f_auto:animated`, is one of the two that fails — Flutter's `Image.network` sends
no useful `Accept` header, so content negotiation has nothing to negotiate with.

**Frame rate is the lever, not quality.** Dropping to 12 fps more than halves the file
where `q_auto:low` shaves 12%. A decorative brand loop at 12 fps reads as film; below
about 10 it reads as a stutter. `du_8` truncates rather than refusing, so an admin who
uploads a thirty-second film gets its opening instead of an error.

That worst case — a busy, full-motion clip — lands at 1.14 MB, under the target. Food film
is usually calmer than a running dog, so real loops should sit well below it.

### Verifying P4 on a device ([[zopiqnow-no-test-files]] — manual, by hand)

Proven without a phone: `assert_hero_motion` accepts the real delivery URL and refuses all
four ways of getting it wrong (not Cloudinary, the raw `.mp4`, an `/image/upload/` URL, and
`fl_awebp` missing); the RPC refuses a bad loop **without disturbing the loop already
stored**; clearing a loop is an ordinary save; and, read as `anon` inside a transaction,
the slide is invisible while switched off and returns `motion_url` once published. The
console typechecks and builds, `flutter analyze` is clean on all three changed Dart files,
and `git diff` on every `pubspec.yaml` and `pubspec.lock` is empty.

1. Console → **Home hero** → edit a slide → **Upload MP4**. Watch the preview: the loop
   must actually *move*. A still frame here is the `fl_awebp` failure above, and this
   preview is the cheapest place in the whole system to catch it.
2. Read the size line. Upload something deliberately awful — a 40 MB phone video — and
   confirm it is **refused with the number in the sentence**, not accepted quietly.
3. Save and publish. On the phone, pull to refresh Home: the still appears first and the
   loop fades in over it. **There must be no blank frame and no flash of white** between
   the two.
4. Add a second slide **without** a loop and publish both. Swipe between them: the loop
   plays on the slide in front of you and the still-only slide is unchanged.
5. Add a *third* slide with its own loop. Now the rule that matters: **only one loop runs
   at a time.** Swipe slowly — the incoming loop stays on its first frame until it passes
   the halfway point, then takes over as the outgoing one parks.
6. Swipe away from a loop and back. It must **resume**, not restart with a re-download —
   that is `TickerMode` parking it rather than the widget being torn down.
7. Turn on **reduce motion** in the OS and cold-start. Every slide shows its **still** —
   specifically the admin's artwork, not a frozen video frame. This is the check that
   distinguishes "not mounted" from "paused", and they look different.
8. Kill the network mid-scroll and cold-start: stills only, no error, no spinner in the
   hero, no gap where a loop would have been.
9. Watch memory and jank on the **Android 10 floor** ([[zopiqnow-android-compat]]) with
   three published loops. Frames decode one at a time, so what sits in RAM is the current
   frame plus the encoded bytes — but decode cost is per frame, per second, on the first
   screen of the app. If the feed judders here, drop `fps_12` before dropping the feature.
10. Leave the app on Home for a few minutes on battery and confirm the loop is not
    measurably draining it. This is the box left unchecked above — if it is a problem,
    that is the evidence that would justify the `battery_plus` ⚠️ task.

### Rules

1. **The still image is mandatory; the loop is an enhancement.** Every failure path —
   slow network, decode failure, reduce-motion, low battery — lands on the still.
2. No audio. A food app that makes noise on the home screen gets uninstalled.
3. One loop on screen at a time.
4. Motion in the hero obeys the same budget the rest of the file already documents:
   no animated layout, everything behind a `RepaintBoundary`.

---

## Suggested order

Not the order they were asked in — this is cheapest-and-safest first, and it front-loads
the decisions.

| # | Task | Effort | Blocked on |
|---|---|---|---|
| ~~1~~ | ~~**P3** Android high refresh rate~~ | **✅ built 2026-07-26** | needs a device pass |
| ~~2~~ | ~~**P1 Tier 1** the live order card~~ | **✅ built 2026-07-25** | needs a device pass |
| ~~3~~ | ~~**P2** admin hero CRUD~~ | **✅ built 2026-07-26** | needs a device pass |
| ~~4~~ | ~~**P4** hero motion loop~~ | **✅ built 2026-07-27** | needs a device pass |
| ~~5~~ | ~~**P1 Tier 2** Android 16 chip + segments~~ | **✅ built 2026-07-25** | needs a device pass |
| 6 | **P1 Tier 3** iOS Live Activities | **weeks** | ⚠️ iOS target 16.1, a Swift extension, and proof iOS builds at all |

P3 first because it is hours and touches nothing else. P1 Tier 1 second because it
reproduces the screenshots on the devices that actually run this app, with nothing
blocking it. P2 before P4 because P4 is a column on P2's table.

Tier 2 jumped the queue because it turned out not to need the `targetSdk` bump it was
filed under: the segmented tracker is reachable on every Android without one, and the
Android 16 half compiles against the `compileSdk 36` the app already had.

---

## Decisions needed from you before any of this starts

1. ~~**P4:** animated WebP (no new dependency) or `video_player` ⚠️?~~ **Answered
   2026-07-27: animated WebP**, and built. Nothing in `pubspec.yaml` moved. Revisit
   `video_player` only if a hero loop ever needs sound or more than ~10 seconds — neither
   of which rule 2 or rule 4 of that slice currently allows.
2. **P1 Tier 2:** ~~approve `targetSdk 35 → 36` ⚠️, or park the Android 16 chip?~~
   **Mostly answered by building it.** The segmented tracker needed no bump and now runs
   on every Android; the Android 16 branch compiles against the existing `compileSdk 36`
   and is gated at runtime. The only question left is narrow: *if a device pass on Android
   16 shows no status-bar chip*, do you want `targetSdk 35 → 36` ⚠️ as its own upgrade
   task to get it? Nothing else depends on the answer.
3. **P1 Tier 3:** is iOS a real target? If yes — has the iOS app ever been built and run
   on a device, and is dropping iOS 13/14/15 acceptable? If iOS is not shipping this
   year, Tier 3 should be deleted from this file rather than carried.
4. ~~**P3:** high refresh rate on customer only, or all three apps?~~ **Answered
   2026-07-26: customer only.** The reasoning is written into P3 above rather than left
   implicit — the kitchen tablet gains nothing, and the rider trades battery for smoothness
   it is not looking at.

---

## Cross-cutting rules

1. **Version freeze holds.** Every ⚠️ above is a separate approved upgrade task with its
   own lockfile diff — never folded into a feature commit.
2. **Android 10 is the floor.** Every tier degrades to something honest there.
3. **The database is the trust boundary.** Hero slides are filtered by RLS, not by the client.
4. **No test files** ([[zopiqnow-no-test-files]]) — hand over manual verification steps instead.
5. **Restrained, premium UI** ([[zopiqnow-clean-ui]]) — no glow, no neon. A hero loop is
   brand film, not an effect.

---

## Sources

- [Progress-centric notifications — Android Developers](https://developer.android.com/about/versions/16/features/progress-centric-notifications)
- [Android 16 features and APIs](https://developer.android.com/about/versions/16/features)
- [Live Updates in Android 16 — droidcon](https://www.droidcon.com/2025/06/11/live-updates-in-android-16-exploring-the-next-evolution-of-notifications/)
- [Get started with Live Activity — Firebase Cloud Messaging](https://firebase.google.com/docs/cloud-messaging/ios/live-activity)
- [FCM via APNs integration — FlutterFire](https://firebase.flutter.dev/docs/messaging/apple-integration/)
