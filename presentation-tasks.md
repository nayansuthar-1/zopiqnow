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
| Hero carousel | `apps/customer/lib/features/home/presentation/widgets/home_hero_carousel.dart` | 1111 lines, slides **hardcoded**, art composed in Dart |

Pinned versions this work has to live inside: Flutter **3.44.5**, Dart SDK `^3.12.2`,
`compileSdk 36`, `targetSdk 35`, `minSdk 24`, iOS deployment target **13.0**,
`firebase_messaging 15.1.6`, `flutter_local_notifications 18.0.1`. Next free migration
is **0052**.

---

## P1 — Live order notifications (the Swiggy lock-screen card)

The reference screenshots are **iOS Live Activities**. That is a specific Apple
feature (ActivityKit, iOS 16.1+), not a push notification with a picture on it, and it
has no single cross-platform equivalent. This is the largest of the four asks by a wide
margin and the only one with no cheap path.

### What is actually being asked for, per platform

| Platform | The real feature | Availability | Reachable today? |
|---|---|---|---|
| iOS | Live Activities / Dynamic Island (ActivityKit) | iOS 16.1+ · 17.2+ for remote *start* | ❌ deployment target is **13.0** |
| Android 16+ | Live Updates — `Notification.ProgressStyle`, status-bar chip, expanded lock screen | API 36, and **requires `targetSdk 36`** | ❌ targetSdk is **35** |
| Android 10–15 | Ongoing notification + `setProgress()` — sits in the shade and on the lock screen, but as a normal notification, no chip, no rich card | API 24+ | ✅ today |

**The honest summary:** the screenshots cannot be reproduced on the devices this app
actually targets. [[zopiqnow-android-compat]] puts the floor at Android 10, and the
rich card only exists on Android 16. Most of the user base gets the third row.

### The three-tier plan

- [ ] **Tier 1 — Android ongoing progress notification (works on the Android 10 floor)**
  - One persistent, non-dismissable notification per live order, updated in place by
    reusing the same notification id
  - Progress bar driven by the status ladder, matching the reference:
    `accepted` 15% → `preparing` 35% → `ready_for_pickup` 55% →
    `out_for_delivery` 75% → `arrived_at_customer` 95% → `delivered` dismiss
  - Headline per state — "Restaurant is preparing your order", "Delivery partner is at
    the restaurant", "Your rider is outside" — plus "Arriving in N mins" from
    `orders.eta_minutes`
  - `setOngoing(true)`, `setOnlyAlertOnce(true)` (silent updates after the first),
    dedicated `order_live` channel at `IMPORTANCE_DEFAULT` so it does not buzz six times
  - Cancel on `delivered` / `cancelled` / `rejected`
  - `flutter_local_notifications 18.0.1` covers all of this — **no new dependency**

- [ ] **Tier 2 — Android 16 Live Updates (`Notification.ProgressStyle`)** ⚠️
  - The status-bar chip and the expanded lock-screen card from the screenshots
  - **Blocked on `targetSdk 35 → 36`**, which is a Play-console-affecting change and a
    version-freeze item in its own right. Worth doing on its own schedule, not folded in
  - `flutter_local_notifications 18.0.1` almost certainly does not expose `ProgressStyle`
    (the API postdates it). **Verify before planning** — if absent, it is either a
    package bump ⚠️ or a small Kotlin platform channel (no new dependency)
  - Must degrade to Tier 1 on anything below API 36. Same notification id, same channel

- [ ] **Tier 3 — iOS Live Activities** ⚠️ **largest single item in this file**
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

- [ ] **Migration 0052 — narrate the states the customer currently isn't told about.**
      `notify_customer_order_update` (0047) deliberately **skips** `preparing` and
      `ready_for_pickup` as "kitchen mechanics". A live tracker needs exactly those. Add
      a `kind = 'order_live'` row for every step so the device has an event to redraw on,
      and keep the existing `order_update` rows as the ones that actually buzz — one
      noisy channel and one silent one, or the customer gets six alerts per order
- [ ] Rider arrival events (`arrived_at_restaurant`, `arrived_at_customer`) fire nothing
      to the customer today. 0049 records them; nothing tells the phone. "Delivery
      partner is at the restaurant" — the second screenshot — is exactly this row
- [ ] Payload carries `order_id`, `status`, `eta_minutes`, `progress` so the device
      redraws without a round trip
- [ ] `send-notification` routes `order_live` to a data-only push (`content-available`),
      not an alerting one

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

- [ ] **Migration 0052/0053 — `hero_slides`**
  - `id`, `title`, `subtitle`, `cta_label`, `cta_target` (deep link or restaurant id),
    `image_url`, `sort_order`, `is_active`, `starts_at`, `ends_at`, `created_at`
  - **RLS:** public `select` for `anon` + `authenticated` where
    `is_active and now() between starts_at and coalesce(ends_at, 'infinity')` —
    a scheduled-but-unpublished slide must not be readable, not merely unrendered
  - Writes via `admin_*` RPCs behind `assert_admin()`, matching the pattern every other
    admin surface uses (0026–0038). **No table-level write grant**
  - `revoke all on function ... from public, anon, authenticated` on every new RPC —
    the 0045 lesson
- [ ] **Console module `apps/admin-web/src/content/HeroSlidesPage.tsx`**
  - Copy the shape of `restaurants/RestaurantsPage.tsx`; reuse `lib/uploads.ts`
    `uploadPhoto()` unchanged for stills
  - List, create, edit, reorder (drag or an integer field — a field is fine and cheaper),
    activate/deactivate, schedule
  - **Live preview at the phone's real aspect ratio.** An admin who cannot see the crop
    will ship a slide with the headline over a face
  - Add the route to `App.tsx` and a nav entry
- [ ] **Customer app**
  - `features/home/data/hero_datasource.dart` + a `heroSlidesProvider`
  - `HomeHeroCarousel` takes `List<HeroSlide>` instead of composing its own slides
  - **Keep the existing in-Dart art as the empty state.** Zero active slides must render
    the carousel that ships today, not a blank band. This is what makes the change safe
    to land before any content exists
  - Keep the motion budget the file already documents: transform/opacity only, behind
    `RepaintBoundary`, all loops off under OS reduce-motion
- [ ] Cache: slides change rarely. A short TTL or a pull-to-refresh invalidation, not a
      fetch per home build

### Rules

1. **The empty state is the current design.** No content, no regression.
2. Slide art is Cloudinary-hosted ([[zopiqnow-cloudinary-images]]), never bundled.
3. An expired or deactivated slide disappears from the *query*, not from a client filter.
4. `cta_target` is validated server-side against something that exists — a hero pointing
   at a delisted restaurant is a dead end on the most prominent surface in the app.

---

## P3 — Run at the device's maximum refresh rate

The smallest item here, and half of it is already done.

- [x] **iOS** — `CADisableMinimumFrameDurationOnPhone` is already `true`
      (`apps/customer/ios/Runner/Info.plist:5`). ProMotion 120 Hz is enabled. **Nothing to do.**
- [x] **Impeller** — default on Android in Flutter 3.44.5.
- [ ] **Android** — `MainActivity.kt` is a bare `class MainActivity : FlutterActivity()`.
      Nothing requests a high-refresh display mode, so on a 90/120 Hz phone whose system
      default mode is 60 Hz, the app renders at 60.

Two ways to fix it:

| Approach | Cost | Verdict |
|---|---|---|
| **Kotlin in `MainActivity`** — enumerate `display.supportedModes`, pick the highest `refreshRate` at the current resolution, set `window.attributes.preferredDisplayModeId`. API 23+, ~20 lines | **no new dependency** | ✅ **recommended** |
| `flutter_displaymode` package — `FlutterDisplayMode.setHighRefreshRate()` | a new pub dependency | ⚠️ needs approval; buys little over the above |

- [ ] Implement the Kotlin route in `apps/customer/android/.../MainActivity.kt`
- [ ] **Match the resolution.** Naively picking the highest-refresh mode can also switch
      resolution and blur the display. Filter to modes matching the current
      `physicalWidth`/`physicalHeight` first, then take the max refresh rate
- [ ] Consider `Surface.setFrameRate()` (API 30+) as the modern signal alongside it
- [ ] Do the same in the **vendor and rider** apps, or write down why not — a kitchen
      tablet gains nothing from 120 Hz and loses battery, so "customer only" is a
      defensible answer, but it should be a decision rather than an oversight
- [ ] **Verify with numbers, not vibes.** `flutter run --profile` plus the performance
      overlay on a 90/120 Hz device. A high-refresh app that drops to 45 fps is *worse*
      than a steady 60 — raising the ceiling raises the cost of every dropped frame
- [ ] Re-check the Android 10 floor after the change ([[zopiqnow-android-compat]])

### Rule

Higher refresh rate is only a win if the frame budget is met. If profiling shows the
home feed cannot hold 120 fps, cap it deliberately rather than shipping judder.

---

## P4 — Admin-uploaded looping video in the hero

Depends on **P2** — same table, same console module, same carousel. Do not start before it.

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

- [ ] **Decide: animated WebP (no dependency) or `video_player`** ⚠️ — everything below
      assumes WebP
- [ ] `hero_slides` grows `motion_url` (nullable) beside `image_url`, and the still stays
      **required** — it is the poster, the reduce-motion fallback, and what shows while
      the loop downloads
- [ ] **`uploads.ts` needs a video path.** `uploadPhoto()` hard-rejects anything not
      `image/*` and caps at 10 MB. An MP4 upload goes to Cloudinary's `/video/upload`
      endpoint with its own preset and its own cap
- [ ] Console: upload the MP4, show the transcoded loop in the same live preview, and
      **state the delivered file size** — an admin who uploads a 40 MB clip should see the
      number before customers pay for it on mobile data
- [ ] Carousel: still first, loop swapped in when decoded. Never a blank frame
- [ ] **Only the visible slide animates.** An off-screen loop is battery spent on nothing
- [ ] **Respect reduce-motion.** `MediaQuery.disableAnimationsOf(context)` — already
      honoured by this file for its own animations — means the still, always
- [ ] Consider pausing loops on low battery / data saver
- [ ] Budget and enforce a cap — target **≤ 1.5 MB** per loop after transcode. Cloudinary
      can enforce it at delivery; the console should refuse worse
- [ ] Profile on the **Android 10 floor** specifically. Animated WebP decode is not free,
      and the hero is the first thing on the first screen

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
| 1 | **P3** Android high refresh rate | hours | nothing |
| 2 | **P2** admin hero CRUD | days | nothing |
| 3 | **P1 Tier 1** Android ongoing progress notification | days | nothing |
| 4 | **P4** hero motion loop | days | P2 + the WebP/video decision |
| 5 | **P1 Tier 2** Android 16 Live Updates | days | ⚠️ targetSdk 36 |
| 6 | **P1 Tier 3** iOS Live Activities | **weeks** | ⚠️ iOS target 16.1, a Swift extension, and proof iOS builds at all |

P3 first because it is hours and touches nothing else. P2 before P4 because P4 is a
column on P2's table. P1 Tier 1 delivers most of the felt value of the screenshots on the
devices that actually run this app.

---

## Decisions needed from you before any of this starts

1. **P4:** animated WebP (no new dependency) or `video_player` ⚠️? *Recommend WebP.*
2. **P1 Tier 2:** approve `targetSdk 35 → 36` ⚠️, or park the Android 16 chip?
3. **P1 Tier 3:** is iOS a real target? If yes — has the iOS app ever been built and run
   on a device, and is dropping iOS 13/14/15 acceptable? If iOS is not shipping this
   year, Tier 3 should be deleted from this file rather than carried.
4. **P3:** high refresh rate on customer only, or all three apps?

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
