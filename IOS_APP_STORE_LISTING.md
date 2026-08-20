# App Store listing — the ZopiQ customer app

**Written 2026-08-20, on Windows, by a session that cannot compile or upload any
of this.** It is the paste-ready half of `IOS_RELEASE_RUNBOOK.md` §6 (Phase D):
every field App Store Connect will ask for, answered from the source rather than
from a template. The Mac session owns the archive and the upload; this file owns
the words and the form answers.

Read `IOS_RELEASE_RUNBOOK.md` first. It is the order of work; this is one step
inside it.

---

## 0. The decision this file was written under

**Customer app only.** Rider and Partner are deliberately held back — see §8.

**The reviewer signs in with a fixed-OTP demo account.** Not a demo Google
account, not a password path. See §4.

---

## 1. Three things that must be true before you submit

None of these are listing copy, and all three will sink a submission.

### B1 — There is no signed build yet

Phase A of the runbook has never been run: no signing certificate, no device
build, no archive. **The App Store Connect record in §2 can be created today
without any of that** — creating the record needs only the bundle id — but
nothing can be submitted until the Mac session has walked A → B → D4.

Create the record early anyway. It is what the `.p8`, TestFlight and the upload
all attach to.

### B2 — Payment has never run on an iPhone

`IOS_HANDOVER.md` §6.3: Razorpay is untested on iOS, and launch C1 made **UPI the
only method the customer app offers**. UPI intent needs
`LSApplicationQueriesSchemes` entries, because the SDK calls `canOpenURL` to
decide which UPI apps to show and iOS answers "not installed" for anything not
declared. The schemes are in the customer's `Info.plist` now, but **no one has
put a real payment through an iPhone.**

A reviewer who reaches the payment screen and cannot pay is a Guideline 2.1
rejection. Put a real order through on a device during Phase A, and confirm the
declared scheme set against Razorpay's current iOS guidance while you are there.

### B3 — The demo account must exist before you fill in §4

The address and code in §4 are placeholders until someone creates them in
Supabase. Do that first, then sign in with them **on a real device** to prove the
path a reviewer will take actually works.

---

## 2. The App Store Connect record

| Field | Value |
|---|---|
| Bundle ID | `com.siteonlab.zopiqnow` |
| SKU | `zopiqnow-customer-ios` |
| Primary language | English (India) |
| Primary category | **Food & Drink** |
| Secondary category | Shopping — the Gifts tab is a real second surface |
| Age rating | **4+** — no objectionable content, no gambling, no unrestricted web |
| Minimum iOS | 14.0 (forced by `google_maps_flutter_ios`; see `IOS_HANDOVER.md` §3.1) |
| Copyright | `2026 Hybrid Monks LLP` |
| Version | `1.0.0` (`apps/customer/pubspec.yaml` is at `1.0.0+16`) |

**URLs** — all four are live already and serve both stores:

| Field | URL |
|---|---|
| Privacy Policy | `https://nayansuthar-1.github.io/zopiqnow/privacy.html` |
| Support URL | `https://nayansuthar-1.github.io/zopiqnow/index.html` |
| Terms of Use (EULA) | `https://nayansuthar-1.github.io/zopiqnow/terms.html` |
| Account deletion | `https://nayansuthar-1.github.io/zopiqnow/delete-account.html` |

Apple requires an **in-app** account-deletion route as well as the documented
page. The app has one; do not let the page stand in for it.

Support email: `zopiqnow@gmail.com`. Legal entity: **Hybrid Monks LLP**.

---

## 3. The copy

Paste as written. Character limits are Apple's and each line below is inside
them.

### App name (30 max)

```
ZopiQ: Food Delivery
```

The in-app display name is `ZopiQ` (`CFBundleDisplayName`) and that is what shows
under the icon — the store name may be longer and should be, for search.

### Subtitle (30 max)

```
Order food from local kitchens
```

### Promotional text (170 max — editable without a new build)

```
Now delivering across Falna, Ranakpur and Sadri. Order from kitchens you already know, watch your rider on the map, and pay by UPI.
```

### Keywords (100 max, comma-separated, no spaces after commas)

```
food delivery,restaurant,order food,takeaway,online food,falna,sadri,ranakpur,rajasthan,local
```

Do not repeat words already in the name or subtitle — Apple indexes those
separately and a repeat wastes the budget.

### Description (4000 max)

```
ZopiQ brings food from your own town to your door.

We are not a nationwide app pretending to know your street. ZopiQ serves a handful of towns in Rajasthan — Falna, Ranakpur and Sadri — and every restaurant on it is one you could walk to. The menus are entered by hand with the restaurant, the prices are the ones they charge, and the rider carrying your order is someone the kitchen knows.

WHAT YOU CAN DO

Browse every kitchen that delivers to your address. Set your address once and the app only ever shows you places that can actually reach it — no scrolling past restaurants that will not deliver to you.

Find vegetarian food fast. A single switch filters the entire app to pure veg, and it stays on until you turn it off.

Watch your order arrive. Once a rider picks up, a live map shows where they are, and you get a notification at every step — accepted, being cooked, picked up, arriving.

Pay by UPI. Checkout runs through Razorpay; the app never sees your PIN or your bank details.

Send a gift. The Gifts tab is a separate set of local shops — flowers, cakes, sweets and more — for the days when food is not what you needed.

Rate what you ate. Reviews are tied to real orders, so what you read on a restaurant's page came from someone who actually ordered from it.

Keep your favourites. The Collection tab remembers the places you go back to.

HOW IT WORKS

Sign in with your email. Add your delivery address — use your phone's location or type it in; both reach every screen. Choose a restaurant, build your order, pay, and follow it on the map until it knocks.

A NOTE ON YOUR LOCATION

ZopiQ asks for your location only to work out your delivery address and show you kitchens that reach it. It is never read in the background, never sold, and never shared for advertising. You can decline and type your address by hand — nothing in the app is closed to you if you do.

Questions, or something wrong with an order? zopiqnow@gmail.com

ZopiQ is operated by Hybrid Monks LLP.
```

**Every claim above is true of this build, which is the point** — a reviewer
checks the description against the app. Two things deliberately *not* claimed:

- **Live Activities / Dynamic Island.** The extension target does not exist yet
  (runbook §5). Add this to the description in the version that ships it, not
  before.
- **WhatsApp order confirmations.** They work, but the UTILITY template is still
  pending Meta's approval, and a listing should not promise a channel that can
  go dark.

### What's New (first version)

```
The first release of ZopiQ on iPhone.
```

---

## 4. App Review Information

### The demo account — do this before submitting

**The customer app signs in with an email OTP.** A reviewer will type an address,
wait for a code that goes to a mailbox they do not own, and be stuck. That is a
fast Guideline 2.1 rejection and it repeats until it is fixed.

> ⚠️ **Corrected 2026-08-20: the fixed-OTP plan below does not exist.** This
> section used to say GoTrue supports pre-set OTPs for specific test *addresses*.
> It does not. Read live from
> `GET https://api.supabase.com/v1/projects/{ref}/config/auth`, the only such
> field is **`sms_test_otp`** — phone numbers, not email:
>
> ```
> "sms_test_otp": null          "sms_test_otp_valid_until": null
> "external_phone_enabled": false      "external_email_enabled": true
> ```
>
> There is no *Test OTPs* control under the Email provider to find, however you
> sign in to the dashboard. **Do not go looking for it.**
>
> **The phone route is also closed, and opening it would be a bug.**
> `external_phone_enabled` is `false` and there is no working SMS provider —
> [[zopiqnow-sms-otp-msg91]] is parked pending DLT. Enabling phone auth so that
> one test number works would make the dead phone field on the login screen look
> alive and fail for every real user.
>
> **What actually works**, since email OTP is the only door: a demo account on a
> **publicly readable disposable mailbox** (a Mailinator-style public inbox), with
> the inbox URL written into the review notes so the reviewer fetches their own
> code without contacting anybody. Two things to prove before relying on it —
> that Brevo delivers to that domain at all, and that the account has a Falna
> address saved. Neither is safe to assume.
>
> **Internal TestFlight needs none of this**: no Beta App Review, no demo
> account. Only external testing and public App Review do.

The original plan, kept for the reasoning rather than the mechanism — it was
chosen over a demo Google account because it changes no app code and weakens no
real account:

1. ~~Supabase Dashboard → **Authentication → Sign In / Providers → Email** →
   *Test OTPs*. Add one entry mapping a demo address to a fixed six-digit code.~~
   **No such control exists.**
2. Use an obvious throwaway address, and a code that is not `123456`.
3. **Sign in with it on a real iPhone before you submit.** A fixed OTP that was
   configured but never exercised is the same as no demo account at all.
4. Add a delivery address inside one of the live towns to that account, so the
   reviewer lands on a populated feed instead of an empty one. An app that looks
   empty gets rejected for being incomplete.

Then fill in **App Review Information → Sign-in required**:

| Field | Value |
|---|---|
| Sign-in required | Yes |
| User name | *(the demo address from step 1)* |
| Password | *(the fixed six-digit OTP — Apple's "password" field is where it goes)* |
| Contact | Nayan Suthar · `zopiqnow@gmail.com` |

### Review notes

```
ZopiQ is a hyperlocal food delivery app operating in three towns in Rajasthan, India: Falna, Ranakpur and Sadri.

SIGNING IN
The app uses a one-time code sent by email. The account provided above is configured with a FIXED code — enter the address, then enter the code above when the app asks for it. No mailbox access is needed.

SEEING THE APP WITH CONTENT
The account already has a saved delivery address in Falna, so restaurants appear as soon as you sign in. The app deliberately shows nothing before an address is set, because it only lists kitchens that can reach you — this is intended behaviour, not an empty state.

LOCATION
Location is requested only while choosing a delivery address, and only when in use. There is no background location in this app. An in-app explanation is shown before the system prompt. Declining is fully supported — the address can be typed by hand and every screen remains reachable.

PAYMENT
Checkout uses Razorpay and offers UPI. If you would prefer not to complete a real payment, the order flow up to the payment sheet demonstrates the app; we are happy to arrange a test order if you would like to see the full path.
```

Adjust the payment paragraph once B2 is settled and you know how UPI actually
behaves on a device.

---

## 5. App Privacy

Answered from `PLAY_DATA_SAFETY.md`, which was itself derived from the schema and
the source rather than a template — but **mapped, not copied**: Apple's data
types are not Google's, and the two forms are read by different machines. The two
must agree in substance; they will not match line for line.

### The three overview answers

| Question | Answer |
|---|---|
| Does this app collect data? | **Yes** |
| Is any data used to track you? | **No** |
| Is any data used for third-party advertising? | **No** |

**"No" to tracking is a real answer, not a hopeful one.** There is no ad SDK and
no analytics SDK in the app. The map ads are our own creatives, and migration
0125's `ad_events` table stores `ad_id`, `kind` and `order_id` — **no user id**.
A view is counted against an order, not against a person, nothing is targeted,
and nothing goes to a data broker. That is outside Apple's definition of
tracking, so **no App Tracking Transparency prompt is required**. If an ad SDK is
ever added, this answer changes and so does the app.

### Data types to declare

Every row below is **collected**, **linked to the user's identity**, and **not
used for tracking**.

| Apple category | Type | Purpose |
|---|---|---|
| Contact Info | Name | App Functionality |
| Contact Info | Email Address | App Functionality |
| Contact Info | Phone Number | App Functionality |
| Contact Info | Physical Address | App Functionality |
| Location | Precise Location | App Functionality |
| Location | Coarse Location | App Functionality |
| Purchases | Purchase History | App Functionality |
| User Content | Photos or Videos | App Functionality |
| User Content | Customer Support | App Functionality |
| User Content | Other User Content | App Functionality |
| Identifiers | User ID | App Functionality |
| Identifiers | Device ID | App Functionality |
| Diagnostics | Crash Data | App Functionality |
| Diagnostics | Other Diagnostic Data | App Functionality |
| Other Data | Other Data Types | App Functionality |

What each one actually is, so you can defend it:

- **Physical Address** — the delivery address, shared with the restaurant and the
  rider. Apple does not ask you to enumerate recipients the way Google does.
- **Precise Location** — read while choosing an address; the pinned coordinates
  are saved with the address so the rider can find the door. **Foreground only.**
- **Photos or Videos** — the profile picture, and nothing else.
- **Customer Support** — the canned messages between customer and rider on a
  live order.
- **Other User Content** — star ratings and review text, shown publicly against
  the customer's first name.
- **User ID** — the Supabase id, attached to Crashlytics reports by
  `CrashReporter.identify` so a customer who phones in can be found.
- **Device ID** — the Firebase push token. Nothing else.
- **Crash Data / Other Diagnostic Data** — Crashlytics. It collects **handled**
  errors as well as crashes, deliberately, and both fall under these two types.
- **Other Data Types** — the optional date-of-birth and gender profile fields. If
  you would rather not declare them, remove the fields from the profile screen;
  do not leave them in and omit them here.

### Do NOT declare

Checked and absent. Ticking one of these declares a capability the app does not
have.

- **Usage Data → Product Interaction / Advertising Data** — no analytics SDK is
  present, and see the tracking note above.
- **Search History** — recent searches are local key-value storage and never
  leave the phone.
- **Browsing History**, Contacts, Health & Fitness, Sensitive Info, Financial
  Info → Payment Info.

**Payment Info is a "no" and it is worth being sure of:** the app never sees a
card number, UPI PIN or bank credential. Razorpay's SDK takes those and hands
back a reference.

> If the app's data collection changes, change this file, the App Privacy form
> and `PLAY_DATA_SAFETY.md` in the same week. A stale answer is itself a
> violation on both stores.

---

## 6. Screenshots

Required at **6.7"**; Apple currently derives the smaller sizes from it, but
check the current requirement in App Store Connect rather than trusting this
line. Capture from the running app **during Phase A** — the device is already in
your hand then, and doing it later is a second setup.

Six, in this order, from the demo account so the content is consistent:

1. The restaurant feed with an address set.
2. A restaurant page with its photo strip and menu.
3. The cart, showing the price breakdown.
4. Live order tracking with the rider on the map.
5. The Gifts tab.
6. Veg mode on, filtering the feed.

Shoot on a real device against the demo account's town. Do not mock these up —
Apple rejects screenshots that do not match the app, and there is nothing here
worth faking.

---

## 7. Build and upload

Detail is in `IOS_RELEASE_RUNBOOK.md` §D4. Three notes that belong with the
listing:

- **Export compliance is already handled.** `ITSAppUsesNonExemptEncryption` is
  `false` in all three `Info.plist` files, so the upload will not ask every time.
  The runbook's "worth doing once" bullet is done.
- **Build numbers come from `$(FLUTTER_BUILD_NUMBER)`** — currently `16`. App
  Store Connect rejects a reused build number by **email, several minutes after
  the upload appears to have succeeded**. Bump the `+n` in
  `apps/customer/pubspec.yaml` for every upload, not every release.
- **TestFlight before review.** Put the build on a real phone through TestFlight
  first. The Android side is already in closed testing; matching that shape is
  the low-risk path.

---

## 8. Rider and Partner — held back, and what they will need

Not in this pass. Two reasons, one of which is new.

**Guideline 4.2.** Both are staff-facing tools, and "business app, sign-in
required, no public value" is a well-worn rejection. The runbook §D0 Trap 2 lays
out the three routes; the choice is still open and does not need making today.

**Neither can do Google Sign-In on iOS, and nobody had noticed.** This is not in
`IOS_HANDOVER.md` and it matters, because a demo Google account is exactly how
the Play reviewer gets into both apps:

- All three apps call `google_sign_in` 7.2.0 from Dart.
- **None** of the three `GoogleService-Info.plist` files carry `CLIENT_ID` or
  `REVERSED_CLIENT_ID`.
- The customer app covers this with `GOOGLE_IOS_CLIENT_ID` and
  `GOOGLE_IOS_URL_SCHEME` in its gitignored `Secrets.xcconfig`, confirmed
  substituting into the built `Info.plist` (`IOS_HANDOVER.md` §0).
- **`apps/rider/ios/Flutter/Secrets.xcconfig.example` declares only
  `MAPS_API_KEY`, and `apps/vendor` has no xcconfig at all.**

So on an iPhone today, the Google button in rider and vendor has nothing to
authenticate against. Before either is submitted, each needs its own **iOS OAuth
client** created for its bundle id (`com.siteonlab.zopiqRider`,
`com.siteonlab.zopiqVendor`), the client id and URL scheme wired the way the
customer app already does it, and the example xcconfigs updated to match.

Until then their only door on iOS is the email OTP — which puts them squarely
back in Trap 1, and the fixed-OTP approach in §4 would have to be repeated for
each.
