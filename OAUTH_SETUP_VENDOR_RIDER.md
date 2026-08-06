# Google Sign-In — the four OAuth clients to register

> **Status: all four registered, 6 Aug 2026**, in project `789936942272` (which
> the console displays as "My First Project"). Kept here because the fingerprints
> are the thing to check first when sign-in fails, and because a new keystore or
> a second Play listing means doing this again.

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
| Name | `Zopiq Partner (Play)` |
| Package name | `com.siteonlab.zopiq_vendor` |
| SHA-1 | `8A:F1:77:21:12:D4:BD:AD:73:62:6A:F0:FD:45:1D:22:AF:5D:1A:F9` |

### Client 4 — Zopiq Rider, as Play signs it

| Field | Value |
|---|---|
| Name | `Rider (Play)` |
| Package name | `com.siteonlab.zopiq_rider` |
| SHA-1 | `54:53:54:BF:19:5F:85:63:0A:08:0B:7C:3E:87:07:B1:1C:C1:09:AE` |

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
- **No Supabase change.** The provider is on and already trusts that client.
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
