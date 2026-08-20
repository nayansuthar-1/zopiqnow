# App Store Connect — the three records, and the answers to fill them with

*Written 2026-08-18 on the Mac, at `ae6a6e2`. Covers §D1–D4 of
`IOS_RELEASE_RUNBOOK.md`, which stops at "fill these in" without saying what to
fill them with.*

Every answer below is derived from what the apps **actually declare and do** —
the `Info.plist` keys, the pubspecs, and `PLAY_DATA_SAFETY.md`, which answered
the same questions for Google and was settled against this codebase on
2026-08-02. Where Apple's form and Google's differ, the difference is called out
rather than papered over.

> ⚠️ **This repository is public.** No account, password, OTP or key goes in this
> file. Everything credential-shaped lives in App Store Connect only.

---

## 0. The three records

| | customer | rider | vendor |
|---|---|---|---|
| Display name | **ZopiQ** | **Zopiq Rider** | **Zopiq Partner** |
| Bundle id | `com.siteonlab.zopiqnow` | `com.siteonlab.zopiqRider` | `com.siteonlab.zopiqVendor` |
| Primary category | Food & Drink | Business | Business |
| Location on the form | Precise, foreground | Precise, foreground + blue bar | **None** |

The camelCase in the two staff bundle ids is deliberate — Apple forbids the
underscores the Android application ids carry. Do not "tidy" them.

Shared across all three:

- Privacy Policy URL — `https://nayansuthar-1.github.io/zopiqnow/privacy.html`
- Support URL / Terms — `https://nayansuthar-1.github.io/zopiqnow/terms.html`
- Account deletion — `https://nayansuthar-1.github.io/zopiqnow/delete-account.html`

Apple requires an in-app deletion route and accepts a documented path; that third
URL is the one to give, and it is the same one Google already took.

---

## 1. ⚠️ App Review sign-in — the rejection to avoid first

All three apps sign in with an **email OTP**. A reviewer will enter an address,
wait for a code that goes to a mailbox they do not have, and stop there. That is
a Guideline 2.1 rejection, and it repeats until it is fixed.

Fill **App Review Information → Sign-in required** for every one of the three.
The cleanest option, and the one that weakens no real account:

> A demo account whose OTP is **fixed**, via Supabase GoTrue's pre-set test
> addresses. The reviewer types the address, types the constant code, and is in.

Record the address and the code **in App Store Connect's own fields** — not in
this file, and not in the repo.

**Do not** tell the reviewer to email you for a code. That is itself a rejection.

Add to the review notes for each app, since a reviewer cannot infer any of it:

- **customer** — that a delivery address must be set before the menu is useful,
  and that typing one by hand reaches every screen the GPS path does.
- **rider** — that the account must already be an approved delivery partner, and
  that the demo account is one. Sign-in succeeding and the app then saying *you
  do not ride for us* looks like a bug and is not.
- **vendor** — the same, for an approved restaurant.

### The second trap: whether the staff apps belong on the public store at all

Rider and vendor are tools for Zopiq's own riders and restaurants. Apple rejects
apps with no use for the general public under **Guideline 4.2**, and
"business app, sign-in required, no public value" is a well-worn rejection.

**This is the project owner's call, not a build decision.** The three routes are
laid out in `IOS_RELEASE_RUNBOOK.md` §D0. Whichever is chosen, put the argument
in the review notes rather than submitting and finding out — the public route is
arguable here precisely because Zopiq's riders and restaurants are independent
businesses rather than employees.

---

## 2. App Privacy — the questionnaire, per app

Answers common to all three, and they matter more than any individual row:

| Question | Answer |
|---|---|
| Used for **tracking** (ATT)? | **No — nothing, anywhere on the form.** No analytics or ad SDK is present in any of the three. |
| Data used for advertising or marketing? | **No** |
| Data sold or shared with data brokers? | **No** — the privacy policy says so plainly, and the form must say the same |
| Encrypted in transit? | **Yes** — HTTPS/TLS to Supabase, Firebase and Razorpay |

Because nothing is used for tracking, **no `NSUserTrackingUsageDescription` and
no ATT prompt is needed** in any of the three, and none is present. Do not add
one.

### 2.1 customer — ZopiQ

| Apple category | Data | Linked to user | Purpose |
|---|---|---|---|
| Contact Info | Name, Email, Phone, Physical Address | Yes | App Functionality |
| Location | Precise **and** Coarse | Yes | App Functionality |
| Purchases | Purchase History | Yes | App Functionality |
| User Content | Photos (profile picture), reviews, canned rider messages | Yes | App Functionality |
| Identifiers | User ID (Supabase), Device ID (FCM token) | Yes | App Functionality |
| Diagnostics | Crash Data, Performance Data | Yes | App Functionality |
| Other Data | Date of birth, gender — optional profile fields | Yes | App Functionality, Product Personalization |

- **Payment Info: No.** Razorpay's SDK takes the card, UPI PIN or bank
  credential and returns a reference; the app never sees one. Do not tick it.
- **Location is foreground only.** `Info.plist` declares
  `NSLocationWhenInUseUsageDescription` and no `Always` key, and there is no
  `location` background mode. It is read while the customer picks a delivery
  address and saved with that address so the rider can find the door.
- Diagnostics is **Yes** because Crashlytics is in all three apps. What goes up:
  the exception, its stack, SDK-gathered device/OS/version context, and the
  Supabase **user id** — which is why it is Linked. No name, email, phone or
  address is ever attached.

### 2.2 rider — Zopiq Rider

Everything in the customer table **except** Purchases, Physical Address and the
optional profile fields, plus:

| Apple category | Data | Linked to user | Purpose |
|---|---|---|---|
| Location | **Precise** | Yes | App Functionality |
| User Content | Photos — KYC documents | Yes | App Functionality |
| Other Data | KYC: licence, insurance, ID, vehicle registration | Yes | App Functionality |

**The one sentence to have ready**, because this is the row that draws scrutiny:

> Precise location is collected only while the rider is carrying an order, so the
> customer can see where their food is. It stops between jobs.

⚠️ **Correcting the runbook here.** §D2 calls this *"precise location in the
background"*, which overstates it on iOS. The rider app requests only
**When In Use** — there is no `NSLocationAlwaysAndWhenInUseUsageDescription` in
its `Info.plist`, and `_settings()` in
`apps/rider/lib/features/jobs/data/location_reporter.dart` pairs
`allowBackgroundLocationUpdates: true` with `showBackgroundLocationIndicator:
true`. Tracking continues while the app is backgrounded **with the blue status
bar visible the whole time**, and it never asks for Always.

That is deliberate and it is the same choice as Android, where
`ACCESS_BACKGROUND_LOCATION` is absent and tracking runs in a foreground service
with a visible notification. Both platforms tell the rider, continuously, that
they are being located. It is also a far easier story to tell App Review than
"Always" would be — so describe it accurately rather than reaching for the
runbook's wording.

### 2.3 vendor — Zopiq Partner

The leanest of the three. **No location at all** — no location key of any kind in
its `Info.plist`, and no location background mode.

| Apple category | Data | Linked to user | Purpose |
|---|---|---|---|
| Contact Info | Name, Email, Phone | Yes | App Functionality |
| User Content | Photos — dish and restaurant photos, order-packing photos | Yes | App Functionality |
| Identifiers | User ID, Device ID | Yes | App Functionality |
| Diagnostics | Crash Data, Performance Data | Yes | App Functionality |

### 2.4 Do NOT tick these, on any of the three

Checked and absent from the code. Ticking one declares a capability that does not
exist, and Apple will ask you to demonstrate it.

Contacts · Calendar · Health & Fitness · Browsing History · Search History ·
Sensitive Info (race, religion, sexual orientation, politics) · Audio Data ·
Gameplay Content · Advertising Data · **Product Interaction / Usage Data**
(no analytics SDK is present) · Payment Info · **anything under Tracking**

---

## 3. Permission strings the reviewer will see

Already written and shipping; listed so they can be checked against the answers
above rather than rediscovered. The declared keys, and only these:

| App | `Info.plist` usage-description keys |
|---|---|
| customer | `NSCameraUsageDescription`, `NSLocationWhenInUseUsageDescription`, `NSPhotoLibraryUsageDescription` |
| rider | `NSCameraUsageDescription`, `NSLocationWhenInUseUsageDescription` |
| vendor | `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription` |

`NSPhotoLibraryAddUsageDescription` is deliberately absent everywhere — these
apps read a photo and never write one back. The vendor plist says so in a comment
directly above its camera key; do not "restore" it.

---

## 4. Screenshots (§D3)

Required at **6.7"**, and at **5.5"** depending on Apple's current rules. Capture
on a real device during the Phase A smoke test rather than as a separate
exercise — the screens to catch are exactly the ones that pass or fail Phase A:

- **customer** — the brand-orange launch, a restaurant menu, the cart, the
  payment screen, and an order in flight with the Live Activity on the Lock
  Screen once §C is done.
- **rider** — the job map with a route drawn, and the earnings screen.
- **vendor** — the orders board with a live order on it.

---

## 5. Export compliance (§D4) — already done

`ITSAppUsesNonExemptEncryption` is **`false` in all three `Info.plist` files**,
verified 2026-08-18. The apps use HTTPS and the platform's own crypto, which is
exempt. This is what stops the questionnaire being asked on every single upload;
nothing further is owed.

Build numbers come from `$(FLUTTER_BUILD_NUMBER)`. App Store Connect rejects a
reused build number, and it does so **by email several minutes after the upload
appears to have succeeded** — so a silent success is not yet a success.

---

## 6. What is still owed before any of this can be submitted

1. **Signing** — `DEVELOPMENT_TEAM` is unset in all three projects. §A2.
2. **A device pass** — nothing here has been seen running on an iPhone.
3. **The staff-app distribution decision** — §1 above, and it changes whether
   records for rider and vendor are created on the public store at all.
4. **Google sign-in on rider and vendor** — broken on iOS until two OAuth
   clients exist. See `IOS_HANDOVER.md` §0.1. It does not block the customer
   app's submission, and it would be a poor thing for a reviewer to find.
