# Play Console — Data safety answers

The exact answers to type into **Play Console → App content → Data safety**, for
the **customer app** (`com.siteonlab.zopiqnow`).

Derived from the schema and the app source on 1 Aug 2026, not from a template.
Every "Yes" below is a column or an SDK that exists; every "No" was checked
rather than assumed. **A wrong data-safety answer is itself a policy violation**,
so if you change what the app collects, change this file and the form in the same
week.

Two things worth knowing before you start:

- **"Collected" means sent off the device.** Recent searches are stored only in
  local key-value storage and never leave the phone, so they are *not* collected
  and must not be declared. Same for the theme and veg-mode preferences.
- **"Shared" means passed to a third party**, and Google does not count your own
  processors (Supabase, Firebase, Cloudinary) as sharing — they process on your
  behalf under contract. It *does* count the restaurant and the delivery partner,
  because those are independent businesses receiving the customer's details.

---

## Overview questions

| Question | Answer |
|---|---|
| Does your app collect or share any of the required user data types? | **Yes** |
| Is all of the user data collected by your app encrypted in transit? | **Yes** — everything goes over HTTPS/TLS to Supabase and Razorpay |
| Do you provide a way for users to request that their data be deleted? | **Yes** |
| Account deletion URL | `https://nayansuthar-1.github.io/zopiqnow/delete-account.html` |
| Has your app been independently reviewed against a global security standard? | **No** — do not tick this |

---

## Data types

For every row: **Collected = Yes**, **Processed ephemerally = No**, and
**"Is this required?"** as marked. None of it is used for advertising or
marketing, and none of it is used for tracking across other apps.

### Personal info

| Data type | Collected | Shared | Required? | Purposes |
|---|---|---|---|---|
| Name | Yes | **Yes** — restaurant and delivery partner | Optional | App functionality, Account management |
| Email address | Yes | No | **Required** | Account management, App functionality |
| Phone number | Yes | **Yes** — restaurant and delivery partner | **Required** (before first order) | App functionality, Account management |
| Address | Yes | **Yes** — restaurant and delivery partner | **Required** (before first order) | App functionality |
| Other info (date of birth, gender) | Yes | No | Optional | App functionality, Personalisation |

> Date of birth and gender are optional profile fields the customer may fill in
> and nothing depends on them. If you would rather not declare them, remove the
> fields from the profile screen — do not leave them in and omit them here.

### Financial info

| Data type | Collected | Shared | Required? | Purposes |
|---|---|---|---|---|
| Purchase history | Yes | No | **Required** | App functionality |

> **Payment info: No.** The app never sees a card number, UPI PIN or bank
> credential — Razorpay's SDK takes those and returns a reference. Do not tick
> "User payment info".

### Location

| Data type | Collected | Shared | Required? | Purposes |
|---|---|---|---|---|
| Approximate location | Yes | No | Optional | App functionality |
| Precise location | Yes | **Yes** — delivery partner | Optional | App functionality |

> Location is read while the customer is choosing a delivery address, and the
> pinned coordinates are saved with the address so the rider can find the door.
> **There is no background location collection in the customer app.** (The rider
> app does collect location in the foreground while on a delivery — that is a
> separate listing with a separate form.)

### Photos and videos

| Data type | Collected | Shared | Required? | Purposes |
|---|---|---|---|---|
| Photos | Yes | No | Optional | App functionality, Personalisation |

> The profile picture only, uploaded to Cloudinary. Nothing else touches the
> photo library.

### Messages

| Data type | Collected | Shared | Required? | Purposes |
|---|---|---|---|---|
| Other in-app messages | Yes | **Yes** — delivery partner | Optional | App functionality |

> The canned messages between customer and rider on an active order.

### App info and performance

| Data type | Collected | Shared | Required? | Purposes |
|---|---|---|---|---|
| Crash logs | **Yes** | No | Optional | App functionality, Diagnostics |
| Diagnostics | **Yes** | No | Optional | App functionality, Diagnostics |

> **Settled 2026-08-02 — this note used to say "answer this one last".** It is
> answered: launch C3 put Firebase Crashlytics in all three apps, so the honest
> answer is now **Yes**, and **Diagnostics must be ticked as a purpose**.
>
> What actually goes to Crashlytics: the exception, its stack trace, and the
> device/OS/app-version context the SDK gathers by itself. Plus the Supabase
> **user id** — set by `CrashReporter.identify` so a customer who phones in can
> be found — which Google counts under *Device or other IDs*, already declared
> below. No name, email, phone or address is ever attached to a report.
>
> It also collects **handled** errors, not only crashes. That is deliberate (the
> 29 July order outage was a caught exception, not a crash) and it does not
> change any answer here — Google's "Crash logs" and "Diagnostics" types cover
> both.
>
> **Not collected in debug builds**: `setCrashlyticsCollectionEnabled(!kDebugMode)`.
> Irrelevant to Play, which only ever sees a release build, but it is why a
> developer's own broken widget never reaches the dashboard.

### Device or other IDs

| Data type | Collected | Shared | Required? | Purposes |
|---|---|---|---|---|
| Device or other IDs | Yes | No | **Required** | App functionality |

> The Firebase push token, which is how an order update reaches the phone.

### User-generated content

| Data type | Collected | Shared | Required? | Purposes |
|---|---|---|---|---|
| Other user-generated content | Yes | No | Optional | App functionality |

> Star ratings and review text, shown publicly on the restaurant's page against
> the customer's first name.

---

## Do NOT tick these

Checked and absent from the customer app. If you tick one of these by accident
you are declaring a capability you do not have, and Google will ask you to prove
it or pull the listing.

- Contacts, Calendar, SMS or call logs
- Health, fitness or medical data
- Browsing history, search history *(local only — see the note at the top)*
- Installed apps, other app performance data
- Race, ethnicity, political or religious beliefs, sexual orientation
- Files and docs, music, other audio, video
- App interactions / in-app search history — no analytics SDK is present
- **Any "used for advertising or marketing" purpose, anywhere on the form**
- **Any "used for tracking" / data sold to third parties** — the privacy policy
  states plainly that this never happens; the form has to say the same thing

---

## The other two apps

The vendor and rider apps go to a closed track, and a closed track still needs a
data-safety form. Neither is filled in yet. The rider one is **not** a copy of
this: it collects **precise location in the foreground while on a delivery**,
plus KYC documents (licence, insurance, ID, vehicle registration) under
"Personal info → Other info", and it needs a foreground-location disclosure in
the listing as well as a prominent in-app disclosure. Do that form separately and
carefully.

---

# The permission register (ship A4, 3 August 2026)

**Read this before answering anything on the Play forms.** What a manifest
*declares* is not what an app *ships*: the customer app declares four permissions
and ships sixteen. The rest arrive from libraries when the manifest merger runs,
and Play lists all of them. Every one below was read out of the **built release
APK** with `aapt2 dump badging`, not out of the source manifests.

    aapt2 dump badging apps/<app>/build/app/outputs/apk/release/app-release.apk

## Customer — 16, of which 4 are declared by us

| Permission | Comes from | Why it is there |
|---|---|---|
| `INTERNET` | ours | Reaching the API and loading imagery. |
| `ACCESS_FINE_LOCATION` | ours | Delivery-address detection. **Needed, see the note below.** |
| `ACCESS_COARSE_LOCATION` | ours | Declared alongside FINE so Android 12+ can offer the user "Approximate". |
| `POST_NOTIFICATIONS` | ours | Order-update pushes; opt-in from Android 13. |
| `WAKE_LOCK` | firebase_messaging | Waking to handle a push. |
| `ACCESS_NETWORK_STATE` | firebase_messaging | Retry/backoff on connectivity. |
| `VIBRATE` | flutter_local_notifications | Notification vibration. |
| `FOREGROUND_SERVICE` | zopiq_live_card | Advancing the live order card. |
| `FOREGROUND_SERVICE_SPECIAL_USE` | zopiq_live_card | **Needs a Play Console declaration — see below.** |
| `POST_PROMOTED_NOTIFICATIONS` | zopiq_live_card | Android 16 "Live Update" treatment; inert below 16. |
| `NFC` | Razorpay checkout SDK | Contactless card entry. **We are UPI-only and never use it.** |
| `READ_BASIC_PHONE_STATE` | Razorpay checkout SDK | Their SIM/carrier detection. |
| `USE_BIOMETRIC` | Razorpay checkout SDK | Their in-SDK authentication. |
| `USE_FINGERPRINT` | Razorpay checkout SDK | As above, older API. |
| `com.google.android.c2dm.permission.RECEIVE` | firebase_messaging | Receiving FCM. |
| `<applicationId>.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` | AndroidX | Self-scoped; protects the library's own broadcasts. |

## Rider — 11, of which 7 are declared by us

`INTERNET`, `POST_NOTIFICATIONS`, `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`,
`FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_LOCATION`, `WAKE_LOCK` are ours;
`ACCESS_NETWORK_STATE`, `VIBRATE`, the C2DM one and the AndroidX one merge in.
Precise location is genuinely required here — the customer watches the rider move
on a map. **`FOREGROUND_SERVICE_LOCATION` is the reason RID-001 was closed**, and
it is also why **`ACCESS_BACKGROUND_LOCATION` is deliberately absent**: tracking
happens in a foreground service with a visible notification, which is the shape
Play prefers and which avoids the background-location review entirely.

## Vendor — 7, of which 2 are declared by us

`INTERNET` and `POST_NOTIFICATIONS`; the rest are `WAKE_LOCK`,
`ACCESS_NETWORK_STATE`, `VIBRATE`, C2DM and AndroidX. **No location, no camera,
no storage.** The leanest of the three.

## Two answers the forms will ask for

**1. `FOREGROUND_SERVICE_SPECIAL_USE` (customer only).** Play makes you justify
this one in the Console, and a vague justification is the usual reason it is
rejected. The text to give them is already in the manifest, as the
`PROPERTY_SPECIAL_USE_FGS_SUBTYPE` property in
`packages/zopiq_live_card/android/src/main/AndroidManifest.xml` — **copy it
verbatim** rather than writing a new sentence. It explains that the service
advances the progress bar and countdown on the live order notification, runs only
while an order is in flight, and stops itself when the order ends. That module's
manifest also records why no *other* foreground-service type fits.

**2. Location, and the prominent disclosure.** Both customer and rider request
foreground location and both need an in-app prominent disclosure before the
system dialog.

**The customer's is now built** (3 Aug) — a sheet that names the data, says what
it is used for, and takes an affirmative "Continue", shown *only* when the system
dialog is actually about to appear. It makes three claims and each is true of
this build, which matters because the reviewer checks them against the app:
foreground only (no `ACCESS_BACKGROUND_LOCATION` in the manifest), never sold or
shared for advertising (matches the privacy policy and the answers above), and
refusable (typing an address by hand reaches every screen the GPS path does).
Both entry points are covered — the address picker sheet and the address form.

**The rider's is now built too** (3 Aug, ship A7), and it is a different
disclosure and a stricter one: the rider app tracks *continuously while on a
delivery*, and its wording says exactly that rather than borrowing the
customer's. Four claims, each true of the build — continuous while carrying and
not between jobs; a foreground-service notification in the shade for as long as
it is on; never sold or shared for advertising; and refusable, since declining
costs the rider nothing but the dot on the customer's map.

Both of the rider's location doors are covered — the job map page and the
location reporter that starts when a delivery begins — and, as with the
customer's, the sheet is keyed to *permission state* rather than to a screen, so
it appears only when the system dialog is genuinely about to be raised and the
second door stays silent.

**What is still owed here is yours, not code: the listing's foreground-location
declaration.** Play requires it for the rider app, and it is a Console form
rather than a manifest change — `ACCESS_BACKGROUND_LOCATION` is deliberately
absent from all three apps, which is what keeps this out of the stricter
background-location review.

## Two things deliberately NOT changed, so they are not re-opened

- **Removing `ACCESS_FINE_LOCATION` from the customer app was considered and
  rejected.** The code asks for `LocationAccuracy.medium`, which reads like coarse
  would do — but the *granted permission is the ceiling*, and Android 12+ fuzzes
  an approximate-only grant to a ~3 km² grid. That picks "Hyderabad" instead of
  "Banjara Hills", which is exactly the failure the manifest comment describes.
  Declaring FINE **and** COARSE together is the correct pattern and is what lets
  the user choose approximate if they want to.
- **Stripping the four Razorpay permissions was considered and rejected for v1.**
  `tools:node="remove"` would do it and NFC in particular is genuinely dead in a
  UPI-only flow — but the payment path has never run against live Razorpay
  (ship S5), and an untested change to it days before a submission is the wrong
  trade. **They cost nothing on the listing:** verified with `aapt2` that the
  Razorpay SDK already ships
  `<uses-feature android:name="android.hardware.nfc" android:required="false"/>`,
  so **no device is filtered out of the Play listing by NFC.** Revisit after the
  first real payment, not before.

The only implied hardware feature across all three apps is
`android.hardware.location` (from the location permissions) plus the
`android.hardware.faketouch` that every app gets. Neither excludes any real
phone, so **no `uses-feature` work is owed.**
