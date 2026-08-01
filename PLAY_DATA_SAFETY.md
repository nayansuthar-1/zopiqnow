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
| Account deletion URL | `https://<your-host>/legal/delete-account.html` |
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
| Crash logs | **See note** | No | — | App functionality, Diagnostics |

> **Answer this one last.** Today the app ships no crash reporter, so the honest
> answer is No. Crashlytics is item C3 on the launch plan; if it is in the build
> you submit, this becomes **Yes / Collected / not shared / Diagnostics**, and
> "Diagnostics" must be ticked as a purpose. Ticking it before the SDK is in is
> as wrong as leaving it out afterwards.

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
