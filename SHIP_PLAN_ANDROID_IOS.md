# Ship plan — Android **and** iOS, both stores

Written 3 August 2026. **This supersedes `LAUNCH_PLAN_2026-08-05.md`**, which was
Android-only and dated to a Tuesday that is now tomorrow. Everything that plan
closed stays closed; what it left open is folded in below.

## What changed, stated plainly

The goal is no longer "a Play listing on the 5th". It is **both apps live on both
stores, as soon as they can be, with no hole in them.** Two consequences follow,
and they point in opposite directions:

- **Features are cut hard.** Anything that is not needed to take an order, cook
  it, deliver it, charge for it, or answer for it afterwards is deferred to after
  both listings are live. The deferred list at the bottom is long on purpose.
- **Security is not cut at all.** A hole that ships is a hole in production, and
  the whole point of shipping early is that strangers arrive. Every item in
  Phase 1 closes before either store sees a build.

**The date honestly.** Android can be submitted within days. iOS cannot be
submitted at all until an Apple Developer Program membership exists (G1) — that
is a paid application with a 24–48 hour approval, and *every* iOS item is
downstream of the certificate it issues. So: **Android submits first, iOS
follows the moment the account clears.** Nothing in Phase 1 is platform-specific,
so the security work counts once for both.

---

## What "loophole-free" means here — the standard each item is held to

Not "we thought about it". These four, concretely:

1. **A stranger holding a release build cannot do anything a customer cannot
   do.** The anon key ships inside every APK and IPA — that is by design, and it
   means *the database is the only guard*. Every check that exists only in Dart
   is not a check.
2. **The server never trusts a number the phone sent.** Prices, totals,
   discounts, payment proof, and role are the server's to decide.
3. **Nothing that costs money or sends mail is unbounded.** Free-to-call and
   expensive-to-answer is the shape of every abuse story.
4. **Every claim on this list was verified against the live system**, not against
   a migration file and not in `psql` as `postgres`. The repo's SQL ledger has
   drifted from the live database four times; `postgres` bypasses RLS,
   `pg_safeupdate`, and every grant.

---

## Phase 0 — yours, and they have lead time. Start today.

Nothing here is code. Every one of them blocks something later.

- [ ] **G1 — Apple Developer Program enrolment.** $99/yr. **This is the iOS
      gate and it is the only one with a queue.** Individual is faster;
      organisation needs a D-U-N-S number and is only worth it if the listing
      must read "Zopiq" rather than your own name. Start it before you read the
      rest of this file.
- [ ] **G2 — Confirm the Play Console account type.** A *personal* account
      registered after Nov 2023 must run a closed test with 12 testers for 14
      continuous days before it can apply for production. An *organisation*
      account need not. This single fact decides whether "live" means public or
      closed, and it changes nothing about the work.
- [ ] **G3 — Razorpay merchant KYC**, if it is not already in. No live keys
      means no real money, and the payment gate (S5) stays disarmed until they
      exist.
- [ ] **G4 — Host `legal/` at a public URL.** The privacy policy, the terms, and
      the web account-deletion page. Both stores require a reachable policy URL
      before they will accept a listing; Play additionally requires the deletion
      route to work without installing the app. A GitHub Pages site is enough.
- [ ] **G5 — Rotate the leaked Resend API key** (audit SEC-007). It has been in
      git history since before the audit. Code cannot un-leak a secret.
- [ ] **G6 — Enable PITR** in the Supabase dashboard (audit SEC-008). Launch week
      with no point-in-time recovery is the one bad day that cannot be undone.
- [x] **G7 — Delete the two dead edge functions.** ✅ **Closed 3 Aug — and it
      was not housekeeping.** `send-order-push` was a **live unauthenticated
      push endpoint**: `verify_jwt: false` at the gateway, no caller check in
      the handler, and it trusted the request body wholesale — an
      attacker-chosen `restaurant_id` rang every device registered to it, with
      attacker-controlled text, using the service-role key. Proven by calling it
      with no credentials at all (200; the probe used a payload that sends
      nothing). Audit SEC-001 was fixed for `send-notification` and its dead
      predecessor was left deployed with the hole intact. Both deleted; the same
      call is now 404. Sources stay in the repo.
- [ ] **G8 — Confirm `support@zopiqnow.com` is a real inbox somebody reads.** It
      is written into both legal documents, the deletion page, and the in-app
      support tile. Both stores email it.
- [ ] **G9 — Choose and record two keystore passwords** for the vendor and rider
      release keystores (A2), and put them somewhere that survives this laptop.
      A lost upload key is a new app listing.
- [ ] **G13 — One knob left: set `rate_limit_verify` to 200.** Two of the three
      are done (`rate_limit_email_sent` and `rate_limit_otp`, both 30 → 200, on
      your call). **`rate_limit_verify` is still 30 and it caps successful
      sign-ins at 30/hour across all three apps**, so the problem below is only
      two-thirds fixed until it moves. My attempt to PATCH it was blocked by the
      permission classifier and I did not work around it. Supabase dashboard →
      Authentication → Rate Limits, or the same Management API call.

      Raising it is safe, and the arithmetic is the argument: a 6-digit code is
      1,000,000 possibilities and `mailer_otp_exp` is 300 seconds, so 200
      verifications/hour buys an attacker **16.7 tries inside one code's
      lifetime — a 0.0017% chance**. Brute force stays impossible; only the
      capacity ceiling moves.

      **Original finding — a launch blocker twice over.** All three were **30 per
      hour, project-wide**: the Supabase defaults, never changed after custom
      SMTP was wired to Brevo. Found by S3.

      1. **Capacity.** Thirty sign-in mails an hour, shared across customer,
         vendor and rider. A launch with any traction stops being able to sign
         anybody in, and the failure looks like "the code never arrived".
      2. **Denial of service.** The 45-second throttle is *per address*, so it
         does not apply across different ones. Anyone can type thirty addresses
         into the sign-in form in about a minute and nobody — in any of the three
         apps — receives a code for the rest of the hour. Unauthenticated, no
         tooling, repeatable.

      **hCaptcha on the auth endpoints is the control that actually fixes (2)**
      — a throughput cap never did, since it is not per-IP and throttles your
      users rather than the attacker. It is off today; it needs client work in
      all three apps and is a post-launch item unless the abuse starts. **Brevo's
      own daily quota is now the real ceiling** — worth knowing what it is.
- [ ] **G11 — Restrict the Google Maps Android key** in the Cloud Console to the
      three package names and their signing-certificate SHA-1s. The key is in
      every APK's manifest and has to be — the Maps SDK reads it from there, and
      `google_maps_flutter` is a real dependency, so it cannot be removed. Key
      restriction is the only control that exists for it. Found by S2.
- [ ] **G12 — Cap the Cloudinary unsigned preset** in the dashboard (audit
      SEC-004): restrict allowed formats, max file size, and folder. The preset
      ships inside every binary by design — an unsigned preset carries no
      secret, but it does let a stranger upload to your account. The real fix is
      signed uploads through an edge function; that is a post-launch item, and
      capping the preset is the launch-week control.
- [ ] **G10 — Access to a Mac with Xcode**, for the run of iOS work in Phase 3.
      The three apps compiled there on 2 August; it is needed again for signing,
      the device run, and the archive upload.

---

## Phase 1 — close the holes. Nothing ships before this is ticked.

Mine unless marked. Ordered by how much of the system each one covers.

- [x] **S1 — Full server-side authorization sweep.** ✅ **Closed 3 Aug —
      migration 0087.** Read from the live database, not from the migrations.
      What it found is below.
- [x] **S2 — What actually ships inside the binaries.** ✅ **Closed 3 Aug** for
      Android, against a real signed release APK. **Clean: nothing unexpected is
      in there.** Probed for all 14 values in `.env`; the ten that must never
      ship — Cloudinary API key and secret, DB password, Supabase access token,
      Resend key, SMTP password, the notify webhook secret, both Ola secrets and
      the Google client secret — are all absent. Present and public by design:
      the anon key, the project URL, the OAuth *web client id*, the Cloudinary
      cloud name. **The one real finding is the known one:** the Cloudinary
      unsigned upload preset (audit SEC-004) is in `libapp.so`. See G11 for the
      Maps key, which is legitimate but needs restricting.

      > **Method note, because it nearly produced a false all-clear:** a plain
      > ASCII `grep` of an APK under-reports. Android's binary manifest stores
      > strings **UTF-16**, so the Maps key is invisible to a normal search and
      > only turned up on a wide-character pass. Any future scan has to do both.
- [x] **S3 — Auth cannot be abused.** ✅ **Closed 3 Aug**, and it closed
      differently from how it was written. Read against the live auth config
      rather than the audit's description.

      **Already correct, verified not assumed:** deleting an account ends every
      session, because `delete_my_account` deletes the `auth.users` row and
      sessions cascade from it (0081). And there is **no account enumeration** —
      `signInWithOtp` creates users by default, so a known and an unknown address
      are indistinguishable. Neither needed work.

      **The audit's premise was stale.** CUS-026 says there is no resend throttle;
      the server has one — `smtp_max_frequency` is 45 seconds between mails to
      the same address. Rider and vendor have no resend button at all, so their
      only send is a one-shot from the sign-in form and the server's 45s covers
      it. Building UI throttles into all three apps would have been theatre.

      **What was actually wrong:** the customer app's resend cooldown was **30
      seconds against a server minimum of 45** — so the button went live fifteen
      seconds early and the resend it invited came back refused. The comment
      above it said the UI "should never let the user hit" the server limit,
      which was true as intent and false as a number. Now 45.

      **An attempt cap was considered and deliberately not built:** `rate_limit_verify`
      is 30/hour, and a 6-digit code needs ~500,000 tries. The server already
      makes brute force impossible; an in-app counter would add code and no
      security. See **G13** for the one number here that *is* dangerous.
- [ ] **S4 — The money path cannot be talked into a discount.** Re-verify, over
      HTTP with a real user token, that item prices, totals, taxes, delivery fee,
      and coupon value are all computed server-side in `place_order` and that no
      client-supplied amount is honoured anywhere — including the Razorpay order
      amount and the refund path.
- [ ] **S5 — Arm the payment gate.** `update public.payment_settings set
      require_verified_payment = true;` the moment `RAZORPAY_KEY_ID` /
      `RAZORPAY_KEY_SECRET` are set as function secrets (G3). Until then, a
      release build already refuses to settle a mock payment — that lock stays.
      **Ends with one real ₹1 payment on a real device, on each platform**; the
      signature path has never run against Razorpay, only against a known-good
      vector.
- [ ] **S6 — Rate-limit what costs money or sends mail.** Not "every RPC" (audit
      SEC-005 is an M and this is not the week) — the four that matter:
      order placement, OTP send, broadcast, and push. Per-user, in the database,
      where it cannot be bypassed by a rebuilt client.
- [ ] **S7 — Edge functions: real auth, not `verify_jwt`.** `verify_jwt` proves a
      request carries a JWT this project signed — and **the anon key is such a
      JWT**, shipped in plaintext in every build. That mistake cost us the Ola
      quota once. Audit every deployed function for what it actually
      authenticates and what it would cost a stranger to call.
- [ ] **S8 — Privileged actions leave a trace.** The admin console is one flat
      role with no MFA (audit SEC-003) and it can release, cancel, and delete
      orders — the order delete is unguarded (migration 0069). Full RBAC is
      deferred; **an append-only audit row for every destructive admin action is
      not.**
- [ ] **S9 — The rider KYC gate is server-side.** Migration 0080 gates five work
      paths on documents. Confirm the gate is in the database and not only in the
      rider app's navigation, and that an expired document blocks the same way a
      missing one does.

### What S1 found, and the rule it leaves behind

**Clean, and better than expected:**

- All 43 public tables have RLS **enabled**. No exceptions.
- Every policy is row-scoped. Not one `using (true)`, and the only write
  policies anywhere are `addresses` and `favourites`, both `user_id = auth.uid()`.
- **There are no views in `public`** — so the commonest Supabase hole of all, a
  `postgres`-owned view without `security_invoker` quietly bypassing RLS, does
  not exist here.
- **Every one of the 70-odd `admin_*` functions asserts admin inside itself.**
  They are all executable by `authenticated`, so the guard has to be in the body,
  and a single omission would have handed any signed-in customer the console.
  There are no omissions.

**One real hole, now closed.** `order_receipt_by_key` was callable by anyone
holding the anon key — the key that ships in plaintext in every APK and IPA.
Confirmed by doing it: `HTTP 200`, unauthenticated. It is `SECURITY DEFINER` and
it takes the user id as an *argument*, so the caller names whose receipt to read;
a `(user_id, idempotency_key)` pair would have returned that order's delivery
address, total and payment id. The key is 128-bit random, so nobody was going to
guess one — but that is luck, not a control. Now `HTTP 401`.

**The mechanism matters more than the instance.** Migration 0086 *tried* to
close it, with `revoke all ... from anon, authenticated`. That line does nothing:
every function in this database is born with EXECUTE granted to **PUBLIC**, and
both roles inherit from PUBLIC. Revoking a role's own grant leaves the one it
inherits. Five other functions were in the same state — `place_order` (reachable
but not exploitable; it raises when `auth.uid()` is null) and four trigger
functions (not directly callable at all). All six revoked.

`alter default privileges ... revoke execute on functions from public` **does not
prevent this here** — tried, and it is a no-op: the stored default-ACL row
already carries no PUBLIC entry and new functions still arrive with one.

> **The rule, and it is now permanent:** every migration that creates a function
> owned by `postgres` must carry its own `revoke execute ... from public`.
> Audit SEC-002 swept 51 functions clean on 30 July; six had come back by 3
> August, one per recent migration. The verification query is in the footer of
> `0087_a_revoke_that_did_nothing.sql` and **must return zero rows before each
> release.**

---

## Phase 2 — Android release engineering

- [x] **A1 — A real app icon**, all three apps, **both platforms.** ✅ **Closed
      3 Aug.** Your three marks from `zopiq-safe`, generated into 5 Android
      densities + a proper **adaptive icon** (background colour sampled per app,
      foreground keyed out to white-on-alpha so the launcher can mask, shadow
      and theme it) and all 15 iOS sizes, **opaque** — Apple rejects an icon
      with an alpha channel. Mark spans 54–60% of the adaptive canvas against a
      66.7% safe zone, so nothing clips. Verified by building the vendor APK and
      confirming `res/mipmap-anydpi-v26/ic_launcher.xml` is inside it. No
      dependency was added: `flutter_launcher_icons` would have moved the
      pubspecs, so the generator ran from a throwaway Dart project outside the
      repo. `pubspec.lock` untouched.
- [ ] **A2 — Release keystores for vendor and rider** (audit REL-001, launch C8).
      Customer already has one. Needs G9.
- [ ] **A3 — R8 on, and proven.** A minified release build is a different binary
      from every build tested so far, and it is exactly where release-only
      crashes live. Confirm reflection-dependent paths (Razorpay, Firebase,
      Live Activity plugin) survive it.
- [ ] **A4 — Manifest and permission minimisation.** Every permission in all
      three manifests justified out loud or removed. Play asks about the
      dangerous ones and a wrong answer is a rejection.
- [ ] **A5 — Build the signed AAB from a clean worktree**, install it on a real
      Android 10 device and a current one, and smoke it before anything is
      uploaded. `main` was unbuildable from a clone once already.

---

## Found on the way — the app was 225 MB (3 Aug, closed)

Found while unzipping the release APK for S2, which is the only reason it was
found at all: **the customer release APK was 225.7 MB, and 198 MB of it was
category artwork.**

`assets/icons_zopiq/*.svg` were not vector art. Each was an `<svg>` element
wrapping a single **1536×1024 base64-encoded PNG**, C2PA generation metadata and
all — so `flutter_svg` parsed 6–9 MB of XML and base64-decoded a megapixel image
to fill a **58 dp** circle. `assets/icons-2.0/*.PNG` were the same story without
the wrapper: 1024² photographs for the same 58 dp slot.

That is roughly 700× more pixels than the screen ever asks for, and it cost
twice — once in download size, once in decode time on the home screen, on the
Android 10 devices this app promises to run well on.

All 50 files are now 256 px, which is still generous: 58 dp at a 4× device pixel
ratio is 232 px. Alpha decides the format, so cut-outs stay PNG and the rest
become JPEG. **103 MB of source art → 3.4 MB, and the APK went 225.7 MB → 68.9
MB** — and that is the fat APK with all three ABIs; the per-device split from an
AAB is far smaller again.

Two things this changes beyond the number:

1. **The `.svg` extension was load-bearing and nobody knew.** Two widgets chose
   the *visual treatment* — floated inside the disc vs cropped to it — by asking
   whether the filename ended in `.svg`. Renaming the files would have silently
   restyled the rail. Both now branch on the folder, which is what they were
   really asking. The two genuine vectors in that folder still render as vectors.
2. **The attribution comment was wrong.** It said the art was Microsoft Fluent
   Emoji, MIT licensed, "see `ATTRIBUTIONS.md`" — the art is not Fluent Emoji,
   and **`ATTRIBUTIONS.md` does not exist in this repo.** `assets/categories/`
   may well be genuine Fluent Emoji and `FLUENT-EMOJI-LICENSE.txt` is still
   there. **This needs your answer before D3/D4**, both of which ask you to
   affirm you have the rights to the content you ship — see the open question in
   Phase 4.

Masters of the originals are kept outside the repo at
`D:\siteonlab\zopiq-safe\art-masters\`, and git has them regardless.

---

## Phase 3 — iOS release engineering

All of it is downstream of G1. Ordered by what blocks what.

- [ ] **X1 — Reserve the three bundle ids** in App Store Connect:
      `com.siteonlab.zopiqnow`, `com.siteonlab.zopiqRider`,
      `com.siteonlab.zopiqVendor`. Free, and it stops someone else taking them.
- [ ] **X2 — Signing.** Distribution certificate, `DEVELOPMENT_TEAM` set in all
      three Xcode projects (it is set in none today), Xcode-managed profiles.
      `flutter build ios` currently fails outright without this.
- [ ] **X3 — APNs auth key.** A `.p8` from the developer portal, uploaded to
      Firebase → Cloud Messaging with the Key ID and Team ID. **One upload covers
      all three apps** — they share the `zopiq-de276` project. Without it, FCM
      has no route to any iPhone and every push fails silently.
- [ ] **X4 — Run all three on a real device**, then work the push chain in order
      rather than guessing: APNs token → FCM token → a `device_tokens` row with
      `platform='ios'` → webhook fired → function logs.
- [ ] **X5 — `PrivacyInfo.xcprivacy` for all three apps.** None of them has one.
      Apple rejects or emails ITMS-91053 for missing required-reason API
      declarations, and this is a submission-time surprise that costs a review
      cycle if it is left to be discovered.
- [ ] **X6 — Crashlytics dSYM upload build phase** (launch I10). Dart errors
      already report from iOS with no work at all; this is what makes *native*
      frames readable. Xcode GUI, not a hand-edited `.pbxproj`.
- [ ] **X7 — Live Activity: cut from v1.** The `ZopiqLiveActivity` target does
      not exist in the customer's `project.pbxproj`, so the live order card is
      Android-only in practice. Building an Xcode app-extension target by hand is
      exactly the kind of work this plan defers. **Decision: ship iOS without
      it**, and add it in the first update.
- [ ] **X8 — Archive, TestFlight, internal test on a real iPhone**, then submit.

---

## Added by request — People, in the console (3 Aug, closed)

Audit **ADM-001** was on the deferred list; it was asked for directly, so it was
built. Migration **0088** and a new **People** page.

**Every person on the platform, in one list**, with role, order counts and
controls to block or unblock. There is no `users` table behind it and there
should not be: a person is a row in `auth.users`, and what they may do lives in
three tables keyed by email (`platform_admins`, `restaurant_staff`,
`delivery_partners`). So the role is **derived**, not stored, and stays right the
day somebody is made staff. Roles report most-privileged-first, because that is
the answer that matters when deciding whether to block someone.

**Three order counts, not one.** `delivered` is a completed sale, `rejected` is a
restaurant refusing, `cancelled` is the order being called off. Someone with ten
orders and nine cancellations is a different person from someone with ten and
nine deliveries, and the list exists to tell them apart. Opening a person shows
their addresses, the restaurants they staff, every order with its line items, and
their moderation history.

**Blocking is real, not cosmetic.** It sets `auth.users.banned_until`, so GoTrue
refuses to issue or refresh their tokens — it survives a reinstall and does not
depend on any client behaving. Two things that alone would not cover:

- **An access token already on the phone stays valid until it expires.** So the
  block also deletes their sessions, *and* a `before insert` trigger on `orders`
  refuses a blocked user outright — same shape as 0084's cash refusal. Without
  it, blocking somebody mid-session left them ordering for up to an hour.
- **It records nothing.** Every block and unblock writes to `user_blocks`, which
  is append-only. That is **the start of S8's audit trail**, put here because
  this is the first power the console has over a *person* rather than a row.

**Two rails, in the database rather than the screen:** you cannot block yourself,
and you cannot block another admin — so locking everyone out takes deliberate
SQL, not one click.

Verified: every rail and the trigger exercised in rolled-back transactions
against live data; all four RPCs refuse `anon` **over HTTP** (401), and refuse a
signed-in non-admin via `assert_admin` in their own bodies; every function
revoked from PUBLIC per 0087's rule, which still reports zero. The console
typechecks and builds.

**Not yet done on a real screen** — the page has not been clicked through in a
browser, and blocking a real person has never been tried end to end. That is a
handover check, and the one worth doing first is: block a test account, confirm
it is signed out and cannot order, then unblock it.

---

## Phase 4 — the two submissions

Play first, App Store as soon as X8 allows. Most of this is yours.

- [ ] **D1 — Store assets, once, for both.** **Icons are done** — A1 also
      produced `<app>-play-512.png` and `<app>-appstore-1024.png` for all three,
      opaque, in the session scratchpad; say where you want them kept and they
      move into the repo. Still owed: feature graphic (Play, 1024×500) and phone
      screenshots at both stores' sizes.
- [ ] **D2 — Play listing**: title, short and full description, category, contact
      email, privacy policy URL (G4), countries = India, release notes.
- [ ] **D3 — Play declarations**: content rating questionnaire, target audience,
      **data safety form** (from `PLAY_DATA_SAFETY.md`, already written and
      already updated for Crashlytics), ads = none, and the financial-features
      question answered consistently with UPI-via-Razorpay.
- [ ] **D4 — App Store listing**: name, subtitle, description, keywords, support
      URL, age rating, **privacy nutrition labels** (the same answers as D3, in
      Apple's format), and export-compliance — `ITSAppUsesNonExemptEncryption` is
      already set in all three Info.plists.
- [ ] **D5 — A reviewer test account, for both stores.** An app that hides
      everything behind an OTP login is rejected without one. Apple's review
      notes need it too, plus a note explaining that vendor and rider are
      separate apps for onboarded partners.
- [ ] **D6 — Submit.** Answer review feedback the same hour it arrives.

> **Open question you have to settle before D3 and D4: where did the dish art
> come from?** The code claimed Microsoft Fluent Emoji under MIT and pointed at
> an `ATTRIBUTIONS.md` that does not exist. The files themselves carry C2PA
> generation metadata, which says AI-generated rather than Fluent Emoji. Both
> stores make you affirm you have the rights to what you ship, so the answer
> decides whether `FLUENT-EMOJI-LICENSE.txt` stays, changes, or is joined by a
> real attributions file. If you generated them, that is a perfectly good answer
> — it just needs to be the one written down.

---

## Phase 5 — regression, on release builds, on both platforms

Not debug builds. Run the whole list on Android and then on iOS.

- [ ] Fresh install → email OTP sign-up → OTP arrives → home
- [ ] Google sign-in → home
- [ ] Browse, open a restaurant, add items, cart totals match the menu
- [ ] Apply a coupon; apply an invalid one and read the refusal
- [ ] Add an address, pick it at checkout
- [ ] Checkout offers **UPI only** — no cash anywhere
- [ ] Place an order → vendor sees it within seconds
- [ ] Vendor accepts with a prep time → customer's ETA updates
- [ ] Rider offered → accepts → pickup code → delivery code at the door
- [ ] Order completes; invoice PDF opens and the tax lines add up
- [ ] Rate the order; the restaurant's rating moves
- [ ] Cancel before accept; the refund path is recorded
- [ ] Push arrives with the app killed, and opens the right screen
- [ ] Account → delete → signed out, cannot sign back in
- [ ] Reinstall → sign up again with the same email works
- [ ] Airplane mode mid-browse: no white screen
- [ ] Double-tap "Place order" on a bad connection: **one** order (0086)
- [ ] iOS only: no Live Activity anywhere in the UI (X7), and permissions prompts
      read sensibly the first time

---

## Deferred until both apps are live — by decision, not oversight

Each is a real gap. None of them stops a first release, and `AUDIT_CHECKLIST.md`
keeps the full list with severities.

| | Why it waits |
|---|---|
| **FEA-001** — "nearby" is a number an admin typed | Fine while you launch one area. Urgent at the second neighbourhood. |
| **UX-002** — no phone-number auth | Email OTP and Google both work. A conversion problem, not a broken app. Highest-value thing in week one. |
| ~~**ADM-001**~~ — no customer management | **Pulled forward and built, 3 Aug** — migration 0088 and the console's People page. See below. **ADM-002**, the support queue, still waits: phone and WhatsApp at launch volume. |
| **SEC-003** — flat admin role, no MFA | One operator: you. S8 buys the audit trail; the rest waits until a second account exists. |
| **PERF-002 / CUS-001** — nothing paginated | Nobody has 25 orders on day one. |
| **CUS-011 / CUS-012 / RID-006** — wallet, referrals, incentives | Growth features. None of them is a launch. |
| **UI-001 / UI-007** — no tablet layouts | Vendor tablets matter when there are vendors on tablets. |
| **API-005 / API-006** — cert pinning, root detection | Meaningful only after the server side (Phase 1) is right. |
| **QA-001** — no tests on the money layer | First thing after both listings are live. Badly-written money tests are worse than none. |
| **iOS Live Activity** (X7) | First update. |

---

## How we work

- **One commit per item**, subject `fix(<area>): <lowercase sentence> (ship <ID>)`,
  or `(audit <ID>)` where the item is an audit finding.
- **Ship-first triage.** If it is not on this list it does not get fixed now — it
  gets written into `AUDIT_CHECKLIST.md` and left there.
- **No refactors.** Every change is the smallest change that closes its item.
- **An RPC is proven over HTTP with a real user's token**, never in `psql` as
  `postgres` — that is how a `where`-less `update` stopped the product taking
  orders for three days.
- **Verify in a clean worktree**, not the tree being worked in.
- **The release build is the build we test.** R8 changes the binary.
- After each session: what closed, what did not, and what that does to the date.
