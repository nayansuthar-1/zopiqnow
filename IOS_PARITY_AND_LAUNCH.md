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

> **Corrected 2026-09-12 from the Mac, which ran the builds.** Four rows below
> were wrong and are fixed in place; the reasoning that produced them is in §1.1.
> The short version: **nothing has a Swift error**, and the two `Secrets.xcconfig`
> rows were read off the wrong machine.

| | customer | rider | vendor |
|---|---|---|---|
| Version committed on `main` **[Mac]** | `1.0.0+30` | `1.0.0+7` | `1.0.0+8` |
| Highest build Apple holds **[Mac, live]** | **21** | none | none |
| `flutter build ios --release` **[Mac]** | ✅ signed, 57.8 MB | ⚠️ signing only | ⚠️ signing only |
| Same build `--no-codesign` **[Mac]** | — | ✅ 46.8 MB | ✅ 29.1 MB |
| Bundle id **[repo]** | `com.siteonlab.zopiqnow` | `com.siteonlab.zopiqRider` | `com.siteonlab.zopiqVendor` |
| `DEVELOPMENT_TEAM` set **[repo]** | ✅ `759C76D23N` | ✅ `759C76D23N` | ✅ `759C76D23N` |
| Deployment target **[repo]** | 14.0 | 14.0 | 14.0 |
| `Runner.entitlements` **[repo]** | `aps-environment` only | `aps-environment` only | `aps-environment` only |
| `GoogleService-Info.plist` **[repo]** | ✅ | ✅ | ✅ |
| App icons (15 PNGs) **[repo]** | ✅ | ✅ | ✅ |
| `ExportOptions.plist` **[repo]** | ✅ | ❌ **missing** | ❌ **missing** |
| iOS OAuth client id — **Mac**, the machine that builds | ✅ set | ❌ **empty** | ❌ **empty** |
| iOS OAuth client id — Windows copy | ✅ set | ✅ set | ✅ set |
| `MAPS_API_KEY` — **Mac** | ✅ set | ✅ set | n/a — no map |
| `MAPS_API_KEY` — Windows copy | ❌ empty | ❌ empty | n/a — no map |
| Live Activity extension target in `project.pbxproj` **[repo]** | ❌ **absent** | n/a | n/a |
| ASC API credentials in `.env` **[repo, Windows copy]** | ❌ absent — they live on the Mac | | |

**The customer app is 9 builds behind on iOS.** Apple's newest is build 21;
`main` is at `1.0.0+30`. Since that upload: reviews page, gift page, the bill's
new shape, beverages on every menu, the armed payment gate, refunds that
actually send, own-orders-only history, the drinks upsell, seven audit fixes and
an empty-cart dialog. Because the next `ship_ios` run bumps to 31, **the "must
be ≥ 22" rule is satisfied automatically** — there is no numbering collision to
work around.

### 1.1 What the Mac's baseline run changed, 2026-09-12

**All three apps compile with zero Swift errors.** Nine builds of unseen Dart,
and not one compile diagnostic. That was the single biggest unknown on this list
and it is now closed — the remaining work is configuration, capabilities and
hardware, not code.

**Rider and vendor did not fail to compile — they failed to sign**, in ~20s,
before the code was built:

```
Your team has no devices from which to generate a provisioning profile.
No profiles for 'com.siteonlab.zopiqRider' were found.
```

The cause is in `project.pbxproj`: **only the customer app has a Release
override** setting `CODE_SIGN_STYLE = Manual` with `Apple Distribution` and the
profile *Zopiq Customer App Store* (lines 710–721). Rider and vendor stay on
Automatic, which wants a registered device. Re-run with `--no-codesign` they
build clean: rider 46.8 MB, vendor 29.1 MB. **This is the same gap as B2** — the
two staff apps were never set up to ship — and an `ExportOptions.plist` alone
will not clear it.

**⚠️ `Secrets.xcconfig` is gitignored, so the Windows copy and the Mac copy are
different files, and the doc was written from the wrong one.** On the Mac, which
is the machine that builds: `MAPS_API_KEY` **is** set for customer and rider (so
**B3 is largely done** — what remains is confirming both keys are restricted to
their bundle ids and that *Maps SDK for iOS* is enabled on the project), and
`GOOGLE_IOS_CLIENT_ID` is set for **customer only**.

**On the OAuth question the Mac's conclusion is too pessimistic, and this is
worth getting right because it changes who does the work.** The Mac read its own
empty files and concluded the iOS clients do not exist. They do: the three
Windows copies carry **three distinct ids**, all under Cloud project
`789936942272` (`…t78n…`, `…s8a6…`, `…5t83…` — different values, not a
copy-paste of one). Three real iOS OAuth clients were created around 2026-08-21
and only the customer's ever reached the Mac.

**So this is a two-minute file copy, not a trip to the Cloud console.** What is
still genuinely unconfirmed is step 3 of that memory: whether all three ids are
in Supabase's `external_google_additional_client_ids`. Until they are, Google
sign-in fails on iOS with the same one sentence as every other Google failure.

Also stale, and corrected in the memory itself: `zopiqnow-ios-parity` says the
apps have *"never been signed"*. The customer app has; rider and vendor have not.

---

## 2. Blockers — nothing ships until these are done

### ~~B1. Nobody has compiled today's `main` for iOS~~ — **closed 2026-09-12**

All three build. Zero Swift errors, zero CocoaPods movement, `pubspec.lock`
byte-identical before and after. See §1.1.

### B0. No iPhone is reachable from the Mac **[Mac]**

> **Corrected 2026-09-12.** This section first called the missing phone "the
> critical path" and said registering a device was the cheap fix for B2. **Both
> were wrong, and wrong in the expensive direction** — they imply you cannot ship
> without hardware, and you can.
>
> **An App Store distribution provisioning profile contains no device list.**
> Device registration is a *development*-profile concern. The customer app is the
> proof: it archived and signed to 57.8 MB on a Mac with no phone attached, and
> `ship_ios.mjs` reports it ready to upload. **All three apps can reach
> TestFlight and the App Store with no iPhone in the building.**

What the missing phone actually blocks is **validation, not shipping**: queue
steps 7, 8 and 9. And the substitute for a USB cable is **TestFlight itself** —
push a build, install it on any iPhone you can reach (yours, a rider's, a
restaurant's), and the validation happens there. Internal TestFlight needs no
Beta App Review and no demo account, so it is a fast loop, not a submission.

The one thing genuinely unavailable either way is a *debugger* attached while it
misbehaves. Crashlytics is already in all three apps and handled errors are
explicitly the point of it — that is the intended answer here.

See §6 for what the simulator does and does not cover.

### B2. Rider and vendor cannot be exported **[repo]**

`apps/rider/ios/ExportOptions.plist` and `apps/vendor/ios/ExportOptions.plist`
do not exist, and `tool/ship_ios.mjs` refuses both apps because of it
(`ship_ios.mjs:134-136`). The customer file is the template; each needs its own
bundle id and its own provisioning-profile name.

**And the plist is only half of it** — §1.1 found the other half: neither app has
a manual-signing Release configuration, so neither can even archive. The whole
chain for each staff app, in order, and every link needs the one before it:

1. **Register the App ID** in the Developer portal — `com.siteonlab.zopiqRider`,
   `com.siteonlab.zopiqVendor`. Tick Push Notifications and Sign In with Apple
   while you are there (§3.1).
2. **Create an App Store distribution provisioning profile** for each.
3. **Set manual signing** on the Release configuration, naming that profile.
4. **Write `ExportOptions.plist`** naming the same profile.
5. **Create the App Store Connect record** — the API cannot, so this is the web
   UI, and it is the single longest-lead item on this list.

On step 3 and the "never hand-edit `project.pbxproj`" rule: **that rule is about
adding targets**, where hand-written UUIDs reliably corrupt the project graph.
Changing `CODE_SIGN_STYLE` in a build configuration that already exists is not
that — it is a settings edit, reversible in one line. Do it in Xcode's Signing &
Capabilities tab anyway, which writes the same thing without the chance of a
typo.

### B3. The Maps key — **mostly done**, two things to confirm **[Mac]**

`MAPS_API_KEY` **is** set for customer and rider on the Mac. It was the Windows
copy that was empty, and that copy builds nothing. What is left is confirming,
in the Cloud console, that each key is **restricted to its own bundle id** and
that **"Maps SDK for iOS" is enabled** — a separate API from the Android one,
off by default. A key that is present but unrestricted or unenabled renders
Google's grey "authorization failure" tile rather than crashing, so it will pass
a build and fail on screen.

**Two client-id files still need copying to the Mac**, and this is the same
class of problem: `GOOGLE_IOS_CLIENT_ID` and `GOOGLE_IOS_URL_SCHEME` are filled
in on Windows for rider and vendor and empty on the Mac. Copy them across; do
not create new clients (§1.1).

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
the whole mechanism is the address. So **Sign in with Apple is required in all
three apps**, and this is a common, fast rejection.

> **Decided 2026-09-12: keep Google, add Sign in with Apple.** The cheap route
> — hiding the Google button on iOS — was considered and rejected: iPhone users
> keep the one-tap sign-in. This is an **explicitly approved exception to
> [[zopiqnow-version-freeze]]**, and the only one; `pubspec.lock` will move, and
> `git diff pubspec.lock` must show *only* the new packages and nothing else
> bumped.

**Scope: the Apple button is iOS-only.** On Android `sign_in_with_apple` falls
back to a browser flow that needs a Services ID, a return URL and a client
secret — a whole second setup for a button no Android user wants and no
guideline requires. Gate it on `Platform.isIOS`.

**What the code needs** (all three apps, mirroring the existing Google path in
`auth_supabase_datasource.dart:138`):

- **Two dependencies.** `sign_in_with_apple`, pinned exactly like every other
  line in these pubspecs; and `crypto` **promoted from transitive to direct** at
  the version already in `pubspec.lock` — a direct dep at the locked version
  changes no resolution, and importing a transitive one is a lint at best and a
  break on the next resolve at worst.
- **The nonce dance, which is not optional.** Generate a raw nonce, hand Apple
  its **SHA-256**, then give Supabase the id token **and the raw nonce** so it
  can check them against each other. `supabase_flutter` 2.8.0 already ships
  `generateRawNonce()` on the auth client (`supabase_auth.dart:402`) — use it
  rather than hand-rolling one. `sha256` is what `crypto` is for.
- **`signInWithIdToken(provider: OAuthProvider.apple, …)`** — the same
  experimental-but-only method the Google path already uses, with the same
  `// ignore: experimental_member_use`.
- ⚠️ **Apple sends the user's name exactly once, ever.** `givenName` and
  `familyName` arrive on the *first* authorization for that Apple ID and are
  `null` on every sign-in afterwards — including after a reinstall. If the first
  response is not captured and written to `zopiq_full_name` there and then, the
  name is gone for good and the only route back is the user revoking the app in
  iOS Settings. This fits the rule the datasource already states — *the
  provider's value is a default, the customer's is an answer* — so write it only
  when `zopiq_full_name` is empty.
- **Hide My Email is a real address, and will be common.** Apple returns
  `…@privaterelay.appleid.com`; the relay forwards, so Brevo order mail still
  arrives. Nothing may assume an email is typeable or memorable, and nothing may
  match a user by address across providers.
- **Its own failure types**, `AppleSignInCancelled` / `AppleSignInFailure`,
  alongside the Google pair in `auth_repository.dart:135`. Dismissing the sheet
  is a choice, not a failure — the Google path already draws that line.

**What only a human can do:**

- **Apple Developer portal** → enable the *Sign In with Apple* capability on all
  three App IDs.
- **Xcode** → add the *Sign in with Apple* capability to all three targets. It
  writes `com.apple.developer.applesignin` into `Runner.entitlements`, which
  currently holds `aps-environment` and nothing else.
- **Supabase** → enable the Apple provider and put all three **bundle ids** in
  its client-ids list. A native-only flow needs no secret key; only the browser
  flow does.

**One follow-on obligation.** Apple requires apps offering Sign in with Apple to
**revoke the token when the account is deleted**. `deleteAccount()` exists
(`auth_supabase_datasource.dart:267`) and does not do this. Not a first-review
blocker, but it is an enforcement item — worth an issue rather than a surprise.

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
| ~~1~~ | ~~Baseline build of all three~~ | — | **done 09-12, zero Swift errors** |
| **0** | **Plug an iPhone into the Mac** (B0) | **you** | 7, 8, 9 — and the cheap fix for 4 |
| 2a | Sign in with Apple: the Dart and the two pubspec lines, all three apps (§3.1) | Windows Claude | 2b |
| 2b | Apple capability on 3 App IDs + 3 Xcode targets; Apple provider + 3 bundle ids in Supabase | **you** | submission |
| 3 | Copy `GOOGLE_IOS_CLIENT_ID` + URL scheme for rider and vendor, Windows → Mac; confirm both Maps keys are restricted and *Maps SDK for iOS* is on | you | Google sign-in, maps |
| 3b | All three iOS client ids into Supabase's authorized client ids | you / Management API | Google sign-in |
| 4 | Rider + vendor: App ID → distribution profile → manual-signing Release config → `ExportOptions.plist` (B2, five steps in order) | you + Mac Claude | their builds |
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

**Housekeeping, not blocking:** `apps/customer/pubspec.yaml` carries an
**uncommitted** bump to `1.0.0+31` on the Windows machine — `main` is at `+30`,
which is what Play alpha holds. It looks like the residue of an aborted
`ship.mjs` run. `ship_ios.mjs` bumps and commits the version itself, so leaving
a stray bump in the tree risks it being swept into an unrelated commit. Revert
it or commit it deliberately; do not just leave it.

**Trap 2 from the runbook is still undecided**: whether rider and vendor belong
on the public App Store at all (Guideline 4.2, "no use for the general public").
Zopiq's riders and restaurants are independent businesses, so the public route is
arguable — but put the argument in the review notes rather than finding out.
Apple Business Manager / Custom Apps is the clean alternative.

---

## 6. What the simulator covers, and what it does not

Added 2026-09-12, because there is no iPhone at the Mac and the honest answer is
"most of it, and the gaps have workarounds".

### Fully covered — do these on the simulator, they are not compromises

| Queue step | Why the simulator is enough |
|---|---|
| **11. App Store screenshots** | The simulator is the *standard* way to produce these — a 6.7" frame is an iPhone 16 Pro Max simulator and `xcrun simctl io booted screenshot`. A device adds nothing |
| **7, in large part.** Smoke-testing nine builds of unseen Dart | Feed, town lock, cart, checkout up to the payment sheet, the new reviews page, the gift page, the bill's new shape, beverages, order history. All Dart, all real |
| **10. The demo account** | Email OTP is a network call. `IOS_RELEASE_RUNBOOK.md` §A4 already documents seeding a Sadri address into `SharedPreferences` so the feed opens populated |
| **Sign in with Apple** (§3.1) | Works, once the simulator is signed into an Apple ID in its own Settings app. **Including the first-authorization name**, which is the half most likely to be got wrong |
| Google sign-in | Works — it is a web auth session |
| Rider map, and location logic | Simulated location (Features → Location → Custom / City Run) exercises the reporter and the map honestly |
| **12. Live Activity rendering** | The Lock Screen card renders in an iOS 16.1+ simulator. Dynamic Island needs a Pro-model simulator. Only *push-driven* updates want a device |

### Not covered, and what to do instead

| Gap | Workaround |
|---|---|
| **9. The ₹1 UPI payment** | **No workaround, and this one is real.** UPI apps cannot be installed on a simulator, so `canOpenURL` returns false for every scheme, Razorpay's intent list comes back empty, and the only payment method the app offers at launch is untestable. This needs a real iPhone with a real UPI app — via TestFlight if not via USB |
| Camera (`image_picker`) | No simulator camera. The photo-library path works; the camera path is device-only. Affects the vendor's dish photos and the rider's handover proof, neither of which is on the customer submission path |
| Real jank, thermals, 3G | The simulator runs on the Mac's CPU and tells you nothing. ENGINEERING_RULES Rule 8's floor is a real-device claim |
| Entitlements, signing, archive | Simulator builds are unsigned — but see B0: none of this needs a *phone*, only a distribution profile |

### ⚠️ Push — probably covered, and worth ten minutes to find out

The old runbook line "a simulator cannot show you APNs" is out of date. **Since
Xcode 14 / macOS 13, an Apple Silicon Mac's simulator receives real remote push
notifications** — `registerForRemoteNotifications` returns a genuine token and
APNs delivers to it. On macOS 26.4 with Xcode 26.6 this should hold.

Two caveats before treating step 8 as closed:

- **Apple Silicon only.** `uname -m` must say `arm64`. On an Intel Mac none of
  this applies and only `xcrun simctl push` — a local fake that bypasses APNs
  entirely — is available.
- **The unknown is Firebase, not Apple.** Our chain is
  `send-notification → FCM → APNs → device`, and `PushService` waits on an APNs
  token before registering (`push_service.dart:230`). Whether `firebase_messaging`
  mints an FCM token against a simulator's APNs token is the thing to test rather
  than assume.

If it works it closes most of step 8, **except the killed-app case**, which is
where the Android equivalent broke and which deserves a real device regardless.
