# iOS parity and launch — what is left before the App Store

**Written 2026-09-12 on Windows**, by reading the repository, not by compiling
it. Everything below is marked with where it came from: **[repo]** means it was
read out of a file in this checkout and is as true as the file; **[Mac]** means
only the Mac can settle it; **[stale]** means an existing doc claims something
this file disagrees with.

Companion files, and the order to trust them in:

1. **This file** — the parity list and the launch queue, current as of today.
2. `IOS_RELEASE_RUNBOOK.md` — the mechanics (signing, APNs, the Live Activity
   target, publishing). Still accurate on *how*; its status table stops at
   2026-08-20.
3. `IOS_APP_STORE_LISTING.md` — every field App Store Connect will ask for,
   written out ready to paste. Still current.
4. `IOS_HANDOVER.md` — the archaeology. Why things are the way they are.

> **Decision recorded 2026-09-12: mobile OTP is not happening.** Email OTP is
> the login for launch, on both platforms. `smsSignInEnabled = false` in
> `apps/customer/lib/features/auth/presentation/pages/email_page.dart:53`
> already compiles the phone path out of the UI, so nothing needs to change for
> this — but it does mean **MSG91/DLT and WhatsApp OTP are out of scope for
> this release** and no iOS task below depends on either.

---

## 0. The one-paragraph summary

There is no iOS *feature* work owed. Every screen the Android apps have, the
iOS apps have too — it is the same Dart. What is owed is (a) **three weeks of
shipped work that has never been compiled or run on an iPhone**, (b) **four
native capabilities Android has and iOS does not**, and (c) **an App Store
review problem the Android side never had** (Guideline 4.8, §3.1). The rider
and vendor apps are further behind than the customer app: neither has ever been
signed, neither has an App Store Connect record, and neither can even be
exported.

---

## 1. Ground truth, 2026-09-12

| | customer | rider | vendor |
|---|---|---|---|
| Version in `pubspec.yaml` **[repo]** | `1.0.0+31` | `1.0.0+7` | `1.0.0+8` |
| Highest build Apple holds **[stale, 08-20]** | 18 | none | none |
| Bundle id **[repo]** | `com.siteonlab.zopiqnow` | `com.siteonlab.zopiqRider` | `com.siteonlab.zopiqVendor` |
| `DEVELOPMENT_TEAM` set **[repo]** | ✅ `759C76D23N` | ✅ `759C76D23N` | ✅ `759C76D23N` |
| Deployment target **[repo]** | 14.0 | 14.0 | 14.0 |
| `Runner.entitlements` **[repo]** | `aps-environment` only | `aps-environment` only | `aps-environment` only |
| `GoogleService-Info.plist` **[repo]** | ✅ | ✅ | ✅ |
| App icons (15 PNGs) **[repo]** | ✅ | ✅ | ✅ |
| `ExportOptions.plist` **[repo]** | ✅ | ❌ **missing** | ❌ **missing** |
| iOS OAuth client id in `Secrets.xcconfig` **[repo, Windows copy]** | ✅ set | ✅ set | ✅ set |
| `MAPS_API_KEY` in `Secrets.xcconfig` **[repo, Windows copy]** | ❌ **empty** | ❌ **empty** | n/a — no map |
| Live Activity extension target in `project.pbxproj` **[repo]** | ❌ **absent** | n/a | n/a |
| ASC API credentials in `.env` **[repo, Windows copy]** | ❌ absent — they live on the Mac | | |

**The customer app is 13 builds behind on iOS.** Apple's newest build, 18, was
uploaded on 2026-08-20 from roughly `1.0.0+21`. Since then: reviews page, gift
page, the bill's new shape, beverages on every menu, the armed payment gate,
refunds that actually send, own-orders-only history, the drinks upsell, seven
audit fixes and an empty-cart dialog. All shared Dart, all of it will come along
for free — **and none of it has been through a Swift compiler or onto an
iPhone.**

**Two memories in the index are now stale and should be corrected:**

- `zopiqnow-vendor-rider-google-ios` says *"no iOS OAuth client exists for any
  bundle id"*. Not true any more — all three `Secrets.xcconfig` files carry a
  `GOOGLE_IOS_CLIENT_ID` under Cloud project `789936942272` **[repo]**. What is
  still unconfirmed is whether all three ids are in Supabase's comma-separated
  **Authorized Client IDs** list **[Mac / dashboard]**.
- `zopiqnow-ios-parity` says the apps have *"never been signed"*. The customer
  app has; rider and vendor have not.

---

## 2. Blockers — nothing ships until these are done

### B1. Nobody has compiled today's `main` for iOS **[Mac]**

Three weeks of Dart has landed since the last iOS build. The failure mode is not
subtle — it is a Swift or CocoaPods error at build time — but it has to be met.
Do this first, for all three apps, before anything else on this list.

### B2. Rider and vendor cannot be exported **[repo]**

`apps/rider/ios/ExportOptions.plist` and `apps/vendor/ios/ExportOptions.plist`
do not exist, and `tool/ship_ios.mjs` refuses both apps because of it
(`ship_ios.mjs:134-136`). The customer file is the template; each needs its own
bundle id and its own provisioning-profile name. Downstream of this: **neither
app has an App Store Connect record, and the API cannot create one** — that is a
human at the web UI, and it is the single longest-lead item on this list.

### B3. The Maps key is empty **[repo, Windows copy — confirm on the Mac]**

`MAPS_API_KEY` is blank in both the customer and rider `Secrets.xcconfig` here.
An iOS Maps key is a *different key* from the Android one — Google restricts iOS
keys by bundle id — and "Maps SDK for iOS" is a separate API that is off by
default on the Cloud project. Empty renders Google's grey "authorization
failure" tile rather than crashing, so it will not stop a build; it will stop
the tracking map and the rider's map from drawing. Two keys are needed, one per
bundle id.

### B4. Push has never been observed arriving on an iPhone **[Mac]**

The server half is proven — `send-notification` v12 is `ACTIVE` with the `apns`
block confirmed byte-identical in the downloaded source (2026-08-20). The APNs
`.p8` was uploaded to `zopiq-de276` the same day, reported by the owner and not
independently checkable. What has never happened is a push landing on a device.
Walk the five links in `IOS_RELEASE_RUNBOOK.md` §4 B3 and stop at the first
failure. Test foregrounded, backgrounded, and **killed** — the killed case is
where Android's equivalent broke.

### B5. Payment has never run on an iPhone **[repo + Mac]**

`razorpay_flutter: 1.4.5` is in the customer app **[repo]** and the payment gate
is armed as of `033ef88` (2026-08-29). The Razorpay iOS SDK hands off to UPI
apps and needs the app to be reachable on the way back. The
`LSApplicationQueriesSchemes` allowlist is in `Info.plist` and is explicitly
marked **"Not verified"** in its own comment — written on a machine with no iOS
toolchain and no Razorpay keys. Separately, **there is no `CFBundleURLScheme`
registered for Razorpay's return callback**; the only URL type declared is
Google's. Confirm against Razorpay's current iOS guidance and test one real ₹1
payment on a real iPhone.

### B6. The demo account for App Review does not exist **[Mac / dashboard]**

`IOS_APP_STORE_LISTING.md` §4 has the full reasoning and the correction that
matters: **GoTrue has no fixed-OTP control for email addresses** — the only such
field is `sms_test_otp`, which is for phone numbers and is irrelevant now that
mobile OTP is off the table. The working answer is a demo account on a publicly
readable disposable mailbox with the inbox URL in the review notes. yopmail is
proven to receive Brevo mail but sits behind an intermittent reCAPTCHA;
`maildrop.cc` and `inboxkitten.com` are un-gated alternatives. **Prove whichever
you pick by hand, end to end, on a real iPhone, before it goes into Test
Information.** Save the account's delivery address **in Sadri** (8 restaurants),
never Falna (1).

---

## 3. Parity gaps — Android has it, iOS does not

These are the real answer to "what is remaining in the iOS app that is completed
in the Android app". All four are native-layer, none is a missing screen.

### 3.1 ⚠️ Sign in with Apple — Guideline 4.8 **[repo — and this is the one that gets you rejected]**

All three apps offer **"Continue with Google"**
(`email_page.dart:268`, `apps/rider/.../auth_pages.dart`,
`apps/vendor/.../sign_in_page.dart`). Apple's Guideline 4.8 requires that an app
offering a third-party login also offer an equivalent option that, among other
things, **lets the user keep their email address private**. Email OTP does not —
the whole mechanism is the address. On a strict reading, **Sign in with Apple is
required in all three apps**, and this is a common, fast rejection.

Two routes, and this is a decision rather than a fix:

| Route | Cost | Risk |
|---|---|---|
| **Hide the Google button on iOS** (`if (!Platform.isIOS)`) | ~10 lines, no new dependency, no version-freeze conflict | None at review. Costs iPhone users the one-tap sign-in |
| **Add Sign in with Apple** | New package + a capability + a Supabase provider + an Edge-side audience | Breaks the version freeze; a real chunk of work |

**Recommendation: hide the button on iOS for launch, add Sign in with Apple in
the first update.** It is reversible, it is small, and it removes the only
review risk on this list that has no workaround.

### 3.2 The Live Activity extension does not exist **[repo]**

`grep ZopiqLiveActivity apps/customer/ios/Runner.xcodeproj/project.pbxproj`
returns **zero matches** — the target was never created. The Swift is all
written and waiting (`apps/customer/ios/ZopiqLiveActivity/*.swift`), the plugin
is complete (`packages/zopiq_live_card/ios/Classes/ZopiqLiveCardPlugin.swift`),
and `Info.plist` already declares `NSSupportsLiveActivities`.

Without the target, `Activity.request` throws, the plugin logs and returns nil,
and the app is fine — it just has no Lock Screen card where Android draws a
custom ongoing notification. **Not a blocker; a visible parity gap.**

This is the one item that genuinely cannot be done by dropping files in — an app
extension is an Xcode target and `project.pbxproj` was deliberately never
hand-edited. `IOS_RELEASE_RUNBOOK.md` §5 has the five steps, including the
critical one: add `ZopiqLiveCardAttributes.swift` to the extension target **as a
reference, not a copy**.

### 3.3 The vendor and rider rings are quieter on iOS, and have no buttons **[repo]**

Android's ring is genuinely call-like: the device ringtone on the **alarm**
stream, `FLAG_INSISTENT` so it repeats until answered, `ongoing` so it cannot be
swiped, and **Accept / Reject actions on the notification itself**
(`apps/vendor/lib/features/notifications/order_ring.dart`, and the rider's
`offer_ring.dart`).

On iOS it degrades to a single `InterruptionLevel.timeSensitive` alert. Two
separate things are missing:

- **The Time Sensitive Notifications capability is not in
  `Runner.entitlements`** — all three entitlements files contain
  `aps-environment` and nothing else **[repo]**. Without
  `com.apple.developer.usernotifications.time-sensitive`, the interruption level
  is requested and ignored, and the ring cannot break through a Focus mode. This
  is a checkbox in Xcode plus an entitlement key, and it is worth doing: it is
  the loudest thing available without Apple's Critical Alerts entitlement, which
  is granted by application only.
- **No `notificationCategories` are registered.** All three
  `DarwinInitializationSettings` are bare
  (`push_service.dart:105`/`170`/`102`), so `AndroidNotificationAction`'s
  Accept/Reject have no iOS counterpart. A vendor on an iPhone must open the app
  to answer an order. Fixable in Dart — a `DarwinNotificationCategory` with two
  `DarwinNotificationAction`s and a matching `categoryIdentifier` on the ring.

Also Android-only and **deliberately so, do not "fix" it**: the alarm-volume
boost (`MainActivity.kt` on both apps). iOS has no supported way to move system
volume, and driving `MPVolumeView`'s slider programmatically is a rejection. The
Dart side already expects the `MissingPluginException`.

### 3.4 Rider background location is declared but unproven **[repo + Mac]**

Android buys "keep reporting while the rider is in Google Maps" with a foreground
service and a visible notification. iOS buys the same thing with the `location`
background mode (declared in `Info.plist` **[repo]**) plus
`allowsBackgroundLocationUpdates`, which `LocationReporter._settings` sets
(`location_reporter.dart:167` **[repo]**). The code is there and correct-looking.
Nobody has watched a fix arrive on an iPhone with another app on screen.

**Xcode still needs Background Modes → Location updates ticked on the rider
target** — the plist declares the mode, the capability is a separate thing Xcode
owns.

Related and already handled, worth not re-breaking: `geo:` URIs are an Android
convention no iPhone handles. `apps/rider/lib/core/launcher.dart:51` branches to
`_navigateIos`, and `comgooglemaps` / `maps` are in
`LSApplicationQueriesSchemes`. Never watched on a device.

### 3.5 Things that look like gaps and are not

- **High refresh rate.** Android asks for it in `MainActivity.kt`; iOS declares
  `CADisableMinimumFrameDurationOnPhone` in `Info.plist`. Parity. ✅
- **Deep links.** Neither platform has any. No `<intent-filter>` beyond LAUNCHER
  on Android, no Associated Domains on iOS. Equal, and fine. ✅
- **Account deletion.** In-app at `Routes.deleteAccount`
  (`delete_account_page.dart`) plus the documented web page. Apple's requirement
  is met. ✅
- **Permission strings.** All three `Info.plist` files carry every
  `NS*UsageDescription` their Android manifest counterpart implies, with the
  reasoning written inline. The rider deliberately has camera but **not** photo
  library; the vendor deliberately has both. Do not add
  `NSPhotoLibraryAddUsageDescription` to any of them. ✅
- **Export compliance.** `ITSAppUsesNonExemptEncryption = false` is in all three.
  No questionnaire per upload. ✅

---

## 4. Remaining in both apps

Not iOS problems. Listed so the "go live and keep building" plan has them in one
place.

| | What | Where it stands |
|---|---|---|
| **P1** | Customer account tiles that say "coming soon" — Payment Methods, Offers, Help & Support, Settings, See Recommendation | Help & Support matters most; phone and WhatsApp cover it at launch volume |
| **P2** | Vendor-side gift management | The customer can browse and buy gifts; a gift seller has no console. `zopiqnow-gift-parity-thread` |
| **P3** | Razorpay live keys | Still test keys (`fe23b73`). Real money needs merchant KYC |
| **P4** | `rate_limit_verify` is still 30/hour | Caps successful sign-ins across all three apps. One dashboard field |
| **P5** | Menu seeding open questions | Lily Café, Celebration, Wing Orbit, Red Chilli — disputed prices and held-back dishes. `zopiqnow-menu-seeding-open-questions` |
| **P6** | ₹999 gift placeholders | `zopiqnow-gift-catalogue-admin` |
| **P7** | No tests on the money layer | QA-001, deliberately deferred until both listings are live |
| **P8** | Flutter suites are red on main | 116/133 at a clean HEAD since 2026-08-15. **Baseline before blaming a change.** Do not write new tests — this project hands over manual steps |
| **P9** | WhatsApp UTILITY template pending Meta | Order confirmation only. Unrelated to login, which stays email |

---

## 5. The queue

Strictly ordered. Each step's failure is cheaper to meet before the next one
starts.

| # | Step | Who | Blocks |
|---|---|---|---|
| 1 | Pull `main`, `flutter pub get`, build all three for a device | Mac Claude | everything |
| 2 | Decide §3.1 (hide Google on iOS, or add Sign in with Apple) and do it | **you**, then Mac Claude | submission |
| 3 | Two iOS Maps keys, into both `Secrets.xcconfig` | you | maps drawing |
| 4 | `ExportOptions.plist` for rider and vendor | Mac Claude | their builds |
| 5 | App Store Connect records for rider and vendor | **you**, web UI — the API cannot | their builds |
| 6 | Xcode capabilities on all three: Push, Background Modes (+ Location on rider), Time Sensitive Notifications | you, GUI | push and the ring |
| 7 | Smoke-test all three on a real iPhone | Mac Claude + you | everything |
| 8 | Walk the push chain to a device, killed-app case included | Mac Claude | push |
| 9 | One real ₹1 Razorpay payment on an iPhone | you | submission |
| 10 | Demo account on an un-gated mailbox, address in Sadri, proven by hand | you | submission |
| 11 | Screenshots at 6.7" from the running app | Mac Claude, `xcrun simctl io` | listing |
| 12 | Live Activity extension target (§3.2) | Mac Claude + you, Xcode GUI | nothing — parity |
| 13 | iOS notification categories for the vendor ring (§3.3) | Mac Claude | nothing — parity |
| 14 | TestFlight all three, then submit the customer app | you | — |

**Trap 2 from the runbook is still undecided**: whether rider and vendor belong
on the public App Store at all (Guideline 4.2, "no use for the general public").
Zopiq's riders and restaurants are independent businesses, so the public route is
arguable — but put the argument in the review notes rather than finding out.
Apple Business Manager / Custom Apps is the clean alternative.
