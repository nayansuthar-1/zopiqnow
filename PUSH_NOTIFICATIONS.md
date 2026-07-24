# Push notifications — setup & deploy checklist

This is the "flip it on" guide for push across all three apps. The **in-app**
notifications are already done and live (migration 0047 + the inbox/bell in each
app). Push is the same events reaching a *dark* screen, and it needs three things
that only you can do: **Firebase projects**, **an Edge Function deploy**, and a
**database webhook**. The code for all of it is here.

---

## How it works (once deployed)

```
event happens ─▶ trigger writes a `notifications` row (0047)
                        │
                        ├─▶ Realtime ─▶ the in-app bell/inbox      (already live)
                        │
                        └─▶ webhook  ─▶ send-notification function ─▶ FCM ─▶ device
```

Every important event already writes a `notifications` row. The webhook fires on
that INSERT and calls `supabase/functions/send-notification`, which finds the
recipient's device tokens (`device_tokens`, keyed by audience since 0047) and
sends the push. **One function serves all three apps.**

> This **supersedes** `send-order-push` (it rang only the kitchen, only on a new
> order). Deploy `send-notification` and point the webhook at `notifications`.
> Do **not** deploy both, or a new order pushes twice.

---

## 1. Firebase (console — yours to do)

**Recommended: one Firebase project, three Android apps.** One project means one
service account sends to all three apps, so the function needs a single secret.

1. In the [Firebase console](https://console.firebase.google.com/), open (or
   create) a project — the vendor's existing `zopiqnow-vendor` project is fine to
   reuse, or make a fresh `zopiqnow` one.
2. Add an **Android app** for each of the three package names:
   - Customer: `com.zopiqnow.app` (confirm in `apps/customer/android/app/build.gradle` → `applicationId`)
   - Rider: `com.zopiqnow.rider` (confirm in `apps/rider/android/app/build.gradle`)
   - Vendor: already added (`zopiqnow-vendor`).
3. For each, download its **`google-services.json`** and drop it at
   `apps/<app>/android/app/google-services.json`. (The vendor already has one.)
4. **Service account:** Project settings → Service accounts → *Generate new
   private key*. Keep the downloaded JSON — it becomes the function secret in §3.

If you instead keep separate Firebase projects per app, you'll set
`FCM_SERVICE_ACCOUNT_CUSTOMER` / `_RIDER` / `_RESTAURANT` (§3) instead of one
shared `FCM_SERVICE_ACCOUNT`.

---

## 2. Device-side wiring (customer & rider)

The **vendor app is already fully wired** — use `apps/vendor/lib/features/notifications/push_service.dart`
and `apps/vendor/android/` as the working reference. Below is the same wiring for
customer and rider. It is not committed because it can't be build-verified here
without the Firebase files above; add it once you have them, then build a
**release** APK on a real device to confirm (a debug run is not proof — see the
INTERNET-permission bug in the rider history).

### 2a. `pubspec.yaml` (customer & rider — versions match the vendor's frozen pins)

```yaml
dependencies:
  firebase_core: 3.8.1
  firebase_messaging: 15.1.6
  flutter_local_notifications: 18.0.1
```

Run `flutter pub get` at the repo root, then **`git diff pubspec.lock`** — these
are already in the lockfile via the vendor, so the diff should be empty. If it
isn't, you've moved a version; revert to what's frozen.

### 2b. `lib/features/notifications/push_service.dart`

Copy the vendor's file and change only the channel id/name. The
`register_device_token` RPC is already audience-aware (0047), so it auto-detects
whether the signed-in user is a customer, rider, or restaurant — the Dart is
otherwise identical.

- **Customer:** channel `order_updates` / "Order updates".
- **Rider:** channel `jobs` / "New jobs".

Drop the vendor-only `chimeNewOrder` method (that's the kitchen's new-order alarm)
unless you want an equivalent. Keep `start()`, `_syncTokenToSession`,
`_registerToken`, `_unregisterCurrentToken`, `_showForeground`, and the top-level
`_onBackgroundMessage`.

### 2c. `lib/main.dart` — start it after Supabase is up

```dart
await Supabase.initialize(/* ... existing ... */);
await PushService.start();   // guarded: no Firebase config = no-op, app still runs
```

`start()` is wrapped end-to-end (`Firebase.initializeApp` in a try/catch), so the
app runs normally even before `google-services.json` exists — push is just inert.

### 2d. Android — `apps/<app>/android/app/src/main/AndroidManifest.xml`

```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<!-- inside <application>: default channel for the FCM notification -->
<meta-data
    android:name="com.google.firebase.messaging.default_notification_channel_id"
    android:value="order_updates"/>   <!-- rider: "jobs" -->
```

⚠️ **Also confirm `<uses-permission android:name="android.permission.INTERNET"/>`
is in `src/main/AndroidManifest.xml`** (not just debug/profile). The rider app
shipped without it once — see the fix in commit `0146dd3`.

### 2e. Android — Gradle (the google-services plugin)

Mirror the vendor exactly:
- `apps/<app>/android/settings.gradle` (or top-level `build.gradle`): the
  `com.google.gms.google-services` plugin (version `4.4.2`) declared.
- `apps/<app>/android/app/build.gradle`: `apply plugin: 'com.google.gms.google-services'`
  and core-library desugaring (`desugar_jdk_libs 2.1.4`) for
  flutter_local_notifications 18, plus `coreLibraryDesugaringEnabled true`.
- Keep `kotlin.incremental=false` in `android/gradle.properties` (both other apps
  have it; without it the Android build fails on Windows).

> The `google-services` plugin **fails the build if `google-services.json` is
> missing**, which is exactly why this step and §1.3 go together — don't apply the
> plugin until the file is in place.

---

## 3. Deploy the function (yours to do — no CLI/Deno on the dev machine)

```bash
# from repo root, with the Supabase CLI logged in and linked to the project
supabase secrets set FCM_SERVICE_ACCOUNT="$(cat path/to/service-account.json)"
supabase functions deploy send-notification --no-verify-jwt
```

`--no-verify-jwt` because the caller is the database webhook (below), which
authenticates with the service-role key in a header, not a user JWT.

If you kept **separate Firebase projects per app**, set the per-audience secrets
instead of the shared one:

```bash
supabase secrets set FCM_SERVICE_ACCOUNT_CUSTOMER="$(cat customer-sa.json)"
supabase secrets set FCM_SERVICE_ACCOUNT_RIDER="$(cat rider-sa.json)"
supabase secrets set FCM_SERVICE_ACCOUNT_RESTAURANT="$(cat vendor-sa.json)"
```

An audience with no service account is skipped (its in-app inbox still works).

---

## 4. The database webhook (Supabase dashboard → Database → Webhooks)

Create one webhook:

- **Table:** `public.notifications`
- **Events:** `INSERT` only
- **Type:** Supabase Edge Function → `send-notification`
- **HTTP headers:** `Authorization: Bearer <SERVICE_ROLE_KEY>`

That's the whole wiring. From here, any event that writes a notification row also
pushes it.

---

## 5. Verify (on a real device)

1. Install the release build on a device and sign in (customer / rider / vendor).
2. Trigger an event:
   - **Customer:** place an order, then accept it from the vendor app → expect an
     "Order confirmed" push.
   - **Rider:** move an order to *preparing* → expect a "New delivery" push.
   - **Vendor:** place an order → expect a "New order" push.
3. Background the app and repeat — the tray notification should arrive with the
   app closed. (Foregrounded, `_showForeground` draws it; that path is the one to
   check first since it needs no lock-screen.)
4. Check `device_tokens` has a row for the signed-in identity, and the function
   logs (`supabase functions logs send-notification`) show `sent > 0`.

### Known follow-up
- **Double-ring on new orders (vendor):** the vendor already chimes in-app on a
  new order via Realtime (`NewOrderAlarm`) *and* would now get a push. Dedupe by
  `order_id` when you turn push on for the vendor, or keep the vendor on in-app
  chime only by not registering its token. (This was flagged when the in-app
  alarm shipped.)
