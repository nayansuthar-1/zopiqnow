# Google Sign-In — the OAuth clients to register

> **Android: all four registered, 6 Aug 2026**, in project `789936942272` (which
> the console displays as "My First Project"). Kept here because the fingerprints
> are the thing to check first when sign-in fails, and because a new keystore or
> a second Play listing means doing this again.
>
> **iOS: none registered.** A different mechanism — bundle ids, not fingerprints
> — and unlike Android it needs a Supabase change too. It is the last section of
> this file.

The code is done and both apps build. Google Sign-In **will not work until these
clients exist**, and the failure is silent-ish: the account sheet opens, you
pick an account, and the device refuses with

    Invalid key value: <sha1>:com.siteonlab.zopiq_vendor

That message only appears in `adb logcat`. On screen it says "Google sign-in
didn't work. Try again, or use your email." — which is why the underlying code is
also written to Crashlytics.

## Where

Google Cloud project **789936942272** — the same one the customer app uses:

```
https://console.cloud.google.com/apis/credentials?project=789936942272
```

**Create credentials → OAuth client ID → Application type: Android.** Four times
(two per app — see below).

> **Check the project, not the project's name.** The console opens on whatever
> was last used, often "My First Project", and it will happily create an Android
> client in the wrong one. Google issues the id token for the `serverClientId`
> audience only when the Android client lives in the *same* project. The check
> that cannot lie: the new client's ID must start with `789936942272-`.

> **"The Android package name and fingerprint are already in use"** on a form you
> only filled once usually means Create was clicked twice. Look for the
> `OAuth client created` toast underneath the dialog — if it is there, the client
> exists and the error is about the duplicate, not the original.

## What to paste

### Client 1 — Zopiq Partner

| Field | Value |
|---|---|
| Name | `Zopiq Partner (Android)` |
| Package name | `com.siteonlab.zopiq_vendor` |
| SHA-1 | `05:F4:0D:21:D1:4E:6C:99:6C:CD:AC:F4:AD:84:47:26:B8:B4:A6:F9` |

### Client 2 — Zopiq Rider

| Field | Value |
|---|---|
| Name | `Zopiq Rider (Android)` |
| Package name | `com.siteonlab.zopiq_rider` |
| SHA-1 | `E9:F8:91:57:A7:0A:77:4D:0A:39:C3:06:96:C4:33:FF:13:10:2A:33` |

Those are read straight from `apps/*/android/app/*.jks` — your **upload**
certificates.

## ⚠️ Then do it again with Play's certificate

**The fingerprints above are not enough on their own.** Play App Signing re-signs
every install with *its* key, so a build installed from Play presents a different
certificate from the one you uploaded. Register that one too — same package name,
second client (Google allows several per package, one per certificate).

### Client 3 — Zopiq Partner, as Play signs it

| Field | Value |
|---|---|
| Name | `Partner (Play, v2)` |
| Package name | `com.siteonlab.zopiq_vendor` |
| SHA-1 | `3D:A2:73:22:45:1B:C3:7F:B5:78:1F:4C:82:ED:05:58:27:6C:70:47` |

### Client 4 — Zopiq Rider, as Play signs it

| Field | Value |
|---|---|
| Name | `Rider (Play, v2)` |
| Package name | `com.siteonlab.zopiq_rider` |
| SHA-1 | `01:3F:99:14:86:F6:F9:5D:A3:2F:E6:61:AF:F8:BE:2F:8D:D6:9D:0E` |

> **Why "v2".** The first pair of Play listings were created with the app IDs
> mistyped as `com.siteonlab.zopiqVendor` / `…zopiqRider`, which Play will not
> let you edit afterwards — the first upload is rejected with *"Your APK or
> Android App Bundle needs to have the package name …"*. The listings were
> deleted and remade, and **a remade listing gets a new app signing key**, so the
> fingerprints registered against the first pair (`8A:F1:77:…` and
> `54:53:54:…`) are dead. Their OAuth clients were left in place rather than
> deleted; they authorise a certificate that no longer exists, which costs
> nothing.
>
> The upload-key fingerprints in clients 1 and 2 were *not* affected — those come
> from the `.jks` files on disk, which the Play listing has no say over.

Where these two came from:

> Play Console → the app → **Test and release → Setup → App signing** →
> *App signing key certificate* → **SHA-1 certificate fingerprint**

Take the **Classical key** column. The *Post-quantum cryptography key* beside it
is not what Google Sign-In matches against, and pasting it registers a
certificate no device will ever present.

The **Upload key certificate** panel lower down that page reads *"Certificate
fingerprints will be shown here after you upload your first app bundle"* until a
release exists. That is why clients 1 and 2 take their fingerprints from the
`.jks` files instead — `keytool -list -v -keystore <path>` — rather than waiting
on a release that is itself waiting on sign-in working.

**This repo has already been bitten by exactly this.** It is why the customer app
has three registrations, not one, and why its notes say to read fingerprints off
the device rather than trusting the console. Skipping this step means sign-in
works perfectly on the build on your desk and fails for every tester.

## What you do NOT need to change

- **No new web client.** All three apps share
  `789936942272-82up4pgu8v6in4vmvnogqhiqa8legtl5...` as the `serverClientId` —
  that is the audience the id token is minted for and the value Supabase checks.
  It is already configured in the Supabase Google provider.
- **No Supabase change — on Android.** The provider is on and already trusts
  the web client, which is the audience an Android id token is minted for.
  **iOS is the exception** and needs one entry per iOS client; see below.
- **No debug fingerprint.** Debug builds of both apps now sign with the release
  certificate (as the customer app already did), so the registrations above cover
  debug and release both.

## Checking it worked

Install a debug build and tap **Continue with Google**:

```bash
cd apps/vendor && flutter run
```

- Signs in and lands in the app → done.
- "You don't work here" screen → **OAuth is fine.** That is the staff gate doing
  its job; the account just has no `restaurant_staff` row. Add one and retry.
- "Google sign-in didn't work" → the registration is wrong. `adb logcat | grep
  "Invalid key value"` prints the fingerprint the device actually presented,
  which is the one to register.

## iOS — three more clients, and this time Supabase *does* change

> **Status: not registered.** Everything above is Android. On an iPhone the
> *Continue with Google* button has nothing behind it until these exist.

iOS does not use the Android clients and does not use the fingerprint mechanism
at all — Google identifies an iOS app by its **bundle identifier**, so each app
needs its own iOS client.

**Create credentials → OAuth client ID → Application type: iOS**, in the same
project `789936942272`. Three times.

| App | Bundle ID | Paste the result into |
|---|---|---|
| Customer | `com.siteonlab.zopiqnow` | `apps/customer/ios/Flutter/Secrets.xcconfig` |
| Partner | `com.siteonlab.zopiqVendor` | `apps/vendor/ios/Flutter/Secrets.xcconfig` |
| Rider | `com.siteonlab.zopiqRider` | `apps/rider/ios/Flutter/Secrets.xcconfig` |

> **The bundle ids are camelCase and the Android package names are not.**
> `com.siteonlab.zopiqVendor` on iOS, `com.siteonlab.zopiq_vendor` on Android.
> They are different identifiers for the same app, and Google will accept either
> in the form without complaint — an Android package name typed into an iOS
> client produces a client that authenticates nothing.

An iOS client has no client secret and no fingerprint. Its page prints an **iOS
URL scheme** — the client id with its dot-separated parts reversed. Copy both
values, rather than deriving the second from the first:

```
GOOGLE_IOS_CLIENT_ID = 789936942272-….apps.googleusercontent.com
GOOGLE_IOS_URL_SCHEME = com.googleusercontent.apps.789936942272-…
```

All three `Info.plist` files already read those two as `GIDClientID` and a
`CFBundleURLScheme`, and all three `Secrets.xcconfig` files already have the
empty slots waiting. The files are **gitignored**, so this is per-machine — it
has to be done again on whichever Mac builds the ipa.

### ⚠️ Supabase must list every iOS client id

This is the step Android genuinely does not need, and it is invisible when you
skip it: Google signs the user in and Supabase refuses the token.

On Android the plugin passes `serverClientId`, so Google mints the id token for
the **web** client — which Supabase already trusts. On iOS the plugin drops
`serverClientId` and Google mints the token for the **iOS** client instead.
Supabase checks `aud` against its own list, does not find it, and rejects a
sign-in Google has already approved. On screen that is the same one sentence as
every other Google failure, which is why this is worth knowing in advance rather
than debugging.

Add each iOS client id to **Supabase → Authentication → Sign In / Up → Google →
Authorized Client IDs**. It is a **comma-separated** list, and it currently holds
two entries: the web client and one other. When this is finished it should hold
the web client plus one per iOS app.

### Checking it worked, on iOS

There is no `adb logcat` here. Run on a **physical iPhone** — the simulator has
no Google account and the sheet cannot complete — and read the Xcode console.

- **The sheet never opens.** `GIDClientID` is empty: the build did not see
  `Secrets.xcconfig`. Check the file exists and that the scheme was rebuilt.
- **The sheet opens, you pick an account, then "Google sign-in didn't work".**
  The token was minted and *Supabase* rejected it — that is the Authorized
  Client IDs list above, not the Cloud console.
- **"You don't work here" / "You don't ride for us".** OAuth is fine. That is the
  staff gate doing its job; the account has no `restaurant_staff` or
  `delivery_partners` row.
