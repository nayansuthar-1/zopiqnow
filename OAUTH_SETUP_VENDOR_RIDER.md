# Google Sign-In — the two OAuth clients to register

The code is done and both apps build. Google Sign-In **will not work until these
two clients exist**, and the failure is silent-ish: the account sheet opens, you
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

**Create credentials → OAuth client ID → Application type: Android.** Twice.

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

Find each app's Play certificate at:

> Play Console → the app → **Test and release → Setup → App integrity** →
> *App signing key certificate* → SHA-1

Both apps now exist, so both certificates exist.

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
