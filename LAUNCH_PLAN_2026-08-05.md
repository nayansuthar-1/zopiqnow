# Launch plan — 5 August 2026

Written 1 Aug 2026, 20:10 IST. **Three days and a bit of wall clock.**

This document is the work queue until launch. It **supersedes
`AUDIT_CHECKLIST.md`** for that period: the audit ranks findings by what they
cost to leave broken over a year, and that is the wrong sort for a ship date.
Everything not named here is deferred by decision, not by oversight — the audit
file keeps the full list and we go back to it on 6 August.

Scope, as decided:

| | Where it goes | Signing |
|---|---|---|
| **Customer app** | Google Play, public | Release keystore ✅ already wired, R8 on |
| **Vendor app** | Closed track / direct APK to onboarded restaurants | debug — **needs a keystore** |
| **Rider app** | Closed track / direct APK to onboarded riders | debug — **needs a keystore** |
| **Admin console** | Already a private web app | n/a |
| **iOS, all three** | **Not on 5 August.** TestFlight from ~8 August | none — no Apple account yet |

Payments: **UPI only, no cash on delivery.** The mock gateway stays wired until
the real Razorpay keys arrive.

---

## Read this first — what "published on 5 August" can actually mean

Three things stand between the code and a public listing, and **none of them are
code**. Check all three tonight, because each has lead time you cannot compress.

1. **Your Play Console account type.** A *personal* developer account registered
   after Nov 2023 must run a closed test with **12 testers for 14 continuous
   days** before it can apply for production access. If that applies to you, a
   public production release on 5 August is not possible at any speed, and the
   fastest real outcome is a closed test *starting* on 5 August. An
   *organisation* account has no such requirement. **Open the console and find
   out which you have — this single fact decides the shape of the launch.**
2. **Review time.** A new developer's first app typically takes a few days to
   review, sometimes longer. Submitting on 4 August does not mean live on 5
   August. Submit as early as the build allows.
3. **Razorpay.** No live keys means no real payments. See PAY below — the plan
   is built so this does not block everything else, but it does block taking
   money.

**So the target is:** everything code-complete, signed, and *submitted* by the
end of 3 August; live on whatever track the account allows on 5 August; promoted
to production the moment review and Razorpay both clear.

Nothing below assumes otherwise. If the account turns out to be an organisation
account and review is fast, 5 August public is genuinely reachable.

---

## The payment decision, stated plainly

You have chosen UPI-only, with the mock gateway until the real keys arrive. That
is fine as a build plan and it is how the code is already structured — the
gateway is one provider binding (`paymentGatewayProvider`), so Razorpay replaces
the binding and nothing else.

One consequence has to be designed around rather than accepted quietly: **the
server currently takes any string as proof of payment** (audit PAY-001). With
the mock, a customer taps "Pay", the app invents a reference, and the order is
placed. On a public track that is free food for anyone who finds it, and a
payment screen that moves no money is also a Play policy problem in its own
right.

So the mock does not merely stay — it gets a lock:

- The Razorpay adapter is built now, behind the existing seam, ready for keys.
- The server learns to verify a real Razorpay signature, so a fabricated
  reference stops working the moment keys are configured.
- A release build **refuses to complete checkout with the mock gateway** unless
  it is explicitly built with `--dart-define=ALLOW_MOCK_PAYMENTS=true`. Testing
  tracks get that flag. The production build cannot get it by accident.

That way the mock never becomes a production incident, and the day the keys land
the swap is a build argument and a redeploy, not a sprint.

---

## Gates — must be true before the app can be published

Ordered by who is blocked on whom. **You** = only you can do it. **Me** = code.

### Tonight, 1 Aug — start these now, they have lead time

| # | What | Who | Time |
|---|---|---|---|
| L0 | Check the Play Console account type (see above). Report which. | You | 5 min |
| L1 | Start the **Razorpay merchant KYC** application if it is not already in. Everything else waits on it and nothing you do later makes it faster. | You | 30 min |
| S1 | **Rotate the leaked Resend API key** (audit SEC-007). It has been in git history since before the audit. | You | 10 min |
| S2 | **Enable PITR** in the Supabase dashboard (audit SEC-008). Launch day with no point-in-time recovery is the one bad day you cannot undo. | You | 5 min |
| A1 | `supabase functions delete send-order-push` — dead since migration 0058 and still deployed (audit API-001). | You | 1 min |
| P1 | Decide where the privacy policy and terms will be **hosted** — they need a public URL before the console will accept the listing. A GitHub Pages site or a page on your existing domain both work. | You | 15 min |

### 2 Aug — the legal gate (LEG-001), which is the real blocker

Play will not list an app that creates accounts and offers no way to delete
them, and will not list any app without a privacy policy URL and a completed
data-safety declaration. This is the largest genuinely-blocking piece of work
left, and it is mine.

| # | What | Who | Time |
|---|---|---|---|
| ✅ L2 | **In-app account deletion** — an Account screen entry, a confirmation that says what is kept and why, and the RPC behind it. Orders cannot simply vanish (tax records, settlements owed to restaurants), so the account is deleted and its orders are anonymised — migration 0081. | Me | 4 h |
| ✅ L3 | **Web account-deletion page.** Play requires a deletion route reachable *without* installing the app. A page on the same host as the policy. | Me + you to host | 1 h |
| ✅ L4 | **Privacy policy + terms**, written against what the app actually collects: phone, email, name, delivery addresses, coarse and precise location, profile photo, device push token. I will write them from the schema, not from a template. | Me | 2 h |
| ✅ L5 | **Data-safety answers** — the exact table to type into the console, derived from the same audit of what is collected. | Me | 1 h |
| ✅ L6 | In-app links to policy and terms from the Account screen, and consent wording at sign-up. | Me | 1 h |

**LEG-001 is closed.** Migration 0081, a deletion screen that says what goes and
what stays, in-app policy and terms, the consent line on the sign-in screen, the
generated pages in `legal/`, and `PLAY_DATA_SAFETY.md`.

**What is still yours on this gate:** host `legal/` at a public URL (P1), and
confirm `support@zopiqnow.com` is a real inbox somebody reads — it is written
into both documents, the deletion page and the in-app support tile. If it should
be a different address, say so and it changes in one constant.

### 2–3 Aug — the app itself

| # | What | Who | Time |
|---|---|---|---|
| ✅ C1 | **Remove cash on delivery from checkout.** UPI becomes the only method offered. Server and vendor/rider apps keep the ability to handle a cash order — that is data that already exists — but no new one can be created. | Me | 1 h |
| ✅ C2 | **Razorpay adapter + server-side signature verification + the mock lockout** described above. Ends with everything ready for keys. | Me | 5 h |
| C3 | **Crash reporting** (audit OBS-001) — Crashlytics in the customer app, and in vendor and rider if time allows. Launching without it means your first bug report is a one-star review. This is the highest-value non-gate item on the list. | Me | 3 h |
| C4 | **Idempotency on `place_order`** (audit CUS-005). A double-tap or a retry on a flaky connection currently places two orders. With prepaid UPI that is two charges. | Me | 2 h |
| ✅ C5 | **Hide the dead Account tiles** (audit UX-001). Done alongside LEG-001 — the legal rows went where they were. All five are gone, and Help & support is the support address rather than a snackbar. | Me | 1 h |
| C6 | **Delivery OTP no longer shown unconditionally** on the tracking card (audit CUS-015). It is the proof-of-delivery code; it should appear when the rider is at the door, not from the moment the order is placed. | Me | 1 h |
| C7 | **`ola-static` gets caller authentication** (audit API-002). It proxies your Ola Maps key with no auth — anyone who finds the URL spends your quota. | Me | 2 h |
| C8 | **Release keystores for vendor and rider**, so the closed-track builds are real builds. Customer already has one. | Me + you for the passwords | 1 h |

**C2 is closed, and PAY-001 with it — pending one statement.** Three pieces:

- **`razorpay-order`** creates the Razorpay order server-side, so the amount is
  fixed by us and not by the phone, and writes a `payment_intents` row.
- **`razorpay-verify`** checks Razorpay's HMAC signature
  (`HMAC_SHA256(order_id|payment_id, key_secret)`), in constant time, and moves
  the intent to `verified`. Its implementation was cross-checked against
  `openssl dgst -sha256 -hmac` on the same input — byte-identical.
- **Migration 0085** adds a second `before insert` guard on `orders`: a UPI order
  must name a **verified, unconsumed** intent belonging to the same customer,
  worth at least the order's total. Consuming it is what stops one payment
  buying two dinners.

**The gate ships off.** `payment_settings.require_verified_payment` is `false`,
because turning it on with no keys would stop the product taking orders — the
outage 0082 just fixed. The day the keys are set:

```sql
update public.payment_settings set require_verified_payment = true;
```

**The mock lockout.** Razorpay is bound always; the *server* says whether it
acts, so the day the keys become function secrets every installed build starts
taking real payments with no new release. What sits behind it depends on the
build: debug gets the mock, a release built with
`--dart-define=ALLOW_MOCK_PAYMENTS=true` gets the mock, and a release without it
gets a refusal. **The production build cannot settle a mock payment by
accident.**

**Still owed, and it needs the keys:** set `RAZORPAY_KEY_ID` and
`RAZORPAY_KEY_SECRET` as function secrets, flip the switch above, and put one
real ₹1 payment through a device — the signature path has never run against
Razorpay, only against a known-good vector. On iOS that same run is I8, and it
is also the check that I1's UPI scheme list is right.

**C1 is closed.** The payment card offers UPI and nothing else — cash was removed
rather than disabled, because a greyed-out row invites the question of when it
comes back. Migration 0084 is the half that makes it true rather than displayed:
a `before insert` trigger on `orders` refuses a new `cod` row, so an old build
with the old screen in it cannot create one either. Existing cash orders are
untouched and every screen that renders them still does — verified against all
34 of them in a rolled-back transaction, which is also why this is a trigger and
not a check constraint.

### 4 Aug — build, test, submit

| # | What | Who | Time |
|---|---|---|---|
| R1 | Build the signed **AAB**, verify it is signed with the upload key and that R8 has not broken anything — a minified release build is a different binary from every build tested so far, and this is exactly where release-only crashes appear. | Me | 2 h |
| R2 | **Full manual regression on a real Android 10 device and one current one** — sign up, browse, cart, checkout, track, rate, delete account. The list is written out in "Manual regression" below. | You + me | 3 h |
| R3 | **Store listing**: title, short and full description, feature graphic, phone screenshots (min 2, realistically 6), app icon, category, contact email, privacy policy URL. | You | 3 h |
| R4 | Content rating questionnaire, target audience, data safety form (from L5), ads declaration, app access instructions **including a test account for the reviewer** — an app that hides everything behind an OTP login will be rejected without one. | You | 1 h |
| R5 | Upload, submit for review on the track your account allows. | You | 30 min |

### 5 Aug

Answer review feedback the same hour it arrives. Promote when Razorpay clears.

---

## iOS — why it is not in the 5 August date, and what it is in instead

This plan was written Android-only and did not say so. It says so now.

**iOS cannot ship on 5 August at any speed, and the reason is not code.** There
is no Apple Developer Program membership. Enrolment is a paid application that
takes 24–48 hours to approve for an individual and longer for an organisation
(D-U-N-S lookup), and *every* remaining iOS item is downstream of the signing
certificate that membership issues. Even with the certificate in hand on 5
August, TestFlight needs a build, and the App Store needs review.

So the honest target is: **enrol now, TestFlight the week of 6 August, App Store
when the Android launch has stopped needing hands.** Nothing on the Android
critical path moves to make that happen.

### Where iOS actually stands — better than "not started"

The three apps are **written, and compiled for a real iPhone** on a Mac on 2
August: customer 208.9 MB, rider 39.8 MB, vendor 22.7 MB, arm64, with all three
suites green (133 / 35 / 62). The Dart layer is one codebase, so **iOS is at
feature parity by construction and stays there** — every fix on this list,
including C1 today, lands on both platforms at once. Info.plists mirror the
manifests, Firebase config is confirmed inside the built `.app`, the deployment
target is 14.0, secrets substitute correctly, and five iOS-specific Dart bugs
were found and fixed before any of it ran.

Read `IOS_HANDOVER.md` §0 before touching any of this. It is the only trustworthy
account of what is proven versus what is merely written down.

### I0–I3 — do not need the Apple account, do them whenever

| # | What | Who | Time |
|---|---|---|---|
| ✅ I0 | **Redeploy `send-notification`.** The `apns` block written 1 Aug had never been deployed, so iOS push could not have arrived even with everything else right. Done 2 Aug — and it carried more than APNs: the same commit added webhook-secret verification, so deploying it blind could have killed *Android* push. The trigger's `x-notify-secret`, `.env`, and the deployed secret's digest were checked to match first. Smoke-tested: wrong secret 403, no secret 403, valid secret with an impossible id 200 and nothing sent. | Me | ✅ |
| ✅ I1 | **UPI intent schemes in the customer `Info.plist`.** C1 made UPI the only way to pay, and on iOS Razorpay's SDK uses `canOpenURL` to decide which UPI apps to offer — undeclared schemes read as "not installed" and the intent list comes back empty. The handover said these were unnecessary; that was true of webview checkout and is no longer true of ours. **The set is unverified** — confirm against Razorpay's iOS guidance when C2 is tested on a device. | Me | ✅ |
| I2 | **Apple Developer Program enrolment.** $99/yr. Individual is faster; organisation needs a D-U-N-S number and is worth it only if the listing should read "Zopiq" rather than your own name. **This is the gate. Start it the moment the Android submission is out of your hands.** | You | 30 min + 1–2 days |
| I3 | **Reserve the three bundle ids** in App Store Connect once I2 clears: `com.siteonlab.zopiqnow`, `com.siteonlab.zopiqRider`, `com.siteonlab.zopiqVendor`. Free, and it stops someone else taking the name. | You | 15 min |

### I4–I9 — need the account, and a Mac

Ordered by what blocks what. None of it is on the 5 August path.

| # | What | Who | Time |
|---|---|---|---|
| I4 | **Signing.** Create the distribution certificate, set `DEVELOPMENT_TEAM` in all three Xcode projects (it is set in none of them today), let Xcode manage profiles. Everything below is downstream. `flutter build ios --debug` currently fails with *"No valid code signing certificates were found."* | You + me | 1 h |
| I5 | **APNs auth key.** Create a `.p8` in the developer portal, upload it to Firebase → Cloud Messaging with the Key ID and Team ID. **One upload covers all three apps** — they share the `zopiq-de276` project, contrary to what the handover's Step 3 originally claimed. Without this, FCM has no route to any iPhone and every push fails silently. | You | 30 min |
| I6 | **Run all three on a device**, then work the push chain in order rather than guessing: APNs token → FCM token → a `device_tokens` row with `platform='ios'` → webhook fired → function logs. I0 has already cleared the last link. | You + me | 2 h |
| I7 | **The Live Activity target.** `ZopiqLiveActivity` appears **zero times** in the customer's `project.pbxproj` — the Swift sources, the extension `Info.plist` and `NSSupportsLiveActivities` all exist, but the Xcode target does not, so the live order card is Android-only in practice. Must be done in the Xcode GUI: hand-writing target UUIDs into a `.pbxproj` is a reliable way to corrupt the project. Recipe is `IOS_HANDOVER.md` §4 Step 5 — including the one checkbox that matters, adding `ZopiqLiveCardAttributes.swift` to the extension **as a reference, not a copy**. | Me at the keyboard | 2 h |
| I8 | **Razorpay on a real iPhone** — the first actual payment through the iOS SDK, and the check that I1's scheme list is right. Downstream of C2 and of live keys. | Me + you | 1 h |
| I9 | **TestFlight build and internal test.** Then the App Store listing, which reuses everything R3/R4 produced for Play — the privacy policy URL, the data-safety answers become Apple's privacy nutrition labels, the same screenshots at Apple's sizes. **Apple requires in-app account deletion too**, and LEG-001 already built it. | You + me | 4 h |

### What is *not* an iOS gap, so nobody goes hunting

- **App icons** are Flutter's default on **both** platforms. Equally behind, not an iOS omission — and a Play blocker in its own right (R3).
- **The vendor app has no `Secrets.xcconfig`.** Correct: it has no map and no Google sign-in, so it has no keys.
- **The rider declines `NSLocationAlwaysAndWhenInUseUsageDescription`** on purpose. WhenInUse plus the `location` background mode is all RID-001 asked for; Always would buy a far more alarming prompt for capability the app never uses.
- **The rider needs no camera strings.** It has no `image_picker` dependency — rider KYC documents are not captured in the app.
- **Push-to-start Live Activities** are deliberately not built. FCM cannot send to a Live Activity token; it needs a direct APNs sender in the edge function, which should not be written blind.

---

## Found on the way — `main` did not compile (1 Aug, closed)

Discovered while verifying LEG-001 in a clean worktree, which is the only reason
it was discovered at all. **The repository could not be built from a clone.**

- The customer app had 9 analyzer errors on `main`; the vendor app had 65.
- Five vendor screens imported two widget files that had never been added to git.
- Seven test files described screens that had since changed, so three suites
  failed — where they compiled at all.
- **The QA-003 fix, which the audit lists as closed, had never been committed.**
  The map bug was still live on `main`.

All of it was sitting in the working tree, written and unsaved — audit ARC-004,
which the report rates *Minor*. It was not minor: R1 builds the release AAB from
a clean checkout, and it would have failed on 4 August with no time to work out
why.

Fixed in five commits (`19a654a`…`84dea9a`). A clean checkout now gives **zero
analyzer errors and three green suites — customer 133, vendor 62, rider 35.**

The lesson for the next three days, and it is now a rule below: verify in a
worktree, not in the tree you are working in.

---

## Found on the way — nobody could place an order (1 Aug, closed)

Reported from the customer app against Paradise Biryani: *"We couldn't place your
order."* **It was every restaurant, every cart, every customer, and it had been
that way since 29 July** — the last order in the book is ZPQ-1044.

Migration 0078, the tax rewrite, added one statement with no `where` clause.
Supabase loads `pg_safeupdate` for the roles PostgREST switches into, so it
raised SQLSTATE 21000 for real customers and for nobody testing through `psql`
as `postgres`. The app only shows database messages for `P0001`, so the actual
error was never displayed or logged anywhere.

Fixed in **migration 0082**, verified over HTTP with a real user's token on COD,
multi-line and UPI carts. The rest of the schema was swept for the same shape;
`place_order` was the only one.

**Two things this changes for the remaining three days:**

1. **An RPC is not proven until it is called over HTTP with a user token.**
   `psql` as `postgres` bypasses `pg_safeupdate`, RLS, and every grant — three of
   the things most likely to break a client. This is now on the rules list below.
2. **C3 (crash reporting) is worth more than its row suggests.** This bug was
   invisible for three days because nothing anywhere recorded the real error. A
   product that cannot take an order and cannot tell you why is the exact failure
   OBS-001 describes, and it has now happened once before launch.

---

## Explicitly cut — and what we accept by cutting it

These are open audit findings we are choosing not to fix before launch. Each is
a real defect; each is survivable at launch volume, and that is the whole
argument.

| Finding | Why it can wait |
|---|---|
| **FEA-001** — "nearby" is a number an admin typed in | Survivable while you launch in one area with a handful of restaurants. Becomes urgent the moment you cover a second neighbourhood. |
| **UX-002** — no phone-number auth | Email OTP and Google sign-in both work. This is a conversion problem, not a broken app. Highest-value thing to build in week one. |
| **ADM-001 / ADM-002** — no customer management, no support queue | You will do support by phone and WhatsApp at launch volume. Feel the pain first, then build the right queue. |
| **PERF-002 / CUS-001** — nothing is paginated | Nobody has 25 orders on day one. |
| **SEC-003** — flat admin role, no MFA | The console has one operator: you. Fix before anyone else gets an account. |
| **SEC-005** — no rate limiting on any RPC | Genuinely risky, genuinely not a three-day job. Watch for abuse; PITR (S2) is the backstop. |
| **SEC-004** — Cloudinary unsigned preset in the APK | Worst case is someone uploading junk to your Cloudinary. Cap the preset in the dashboard as a stopgap. |
| **CUS-011, CUS-012, RID-006** — wallet, referrals, incentives | Growth features. None of them is a launch. |
| **UI-007 / UI-001** — no tablet layouts | The customer app is a phone app. The vendor tablet issue matters when you have vendors on tablets. |
| **QA-001** — no tests on the money layer | Uncomfortable, and honest: there is no time to write them properly before Tuesday, and badly-written money tests are worse than none. First thing on 6 August. |

Everything else in `AUDIT_CHECKLIST.md` is deferred by default.

---

## Manual regression — the list for R2

Run on a real device, on the signed release build, not a debug build.

- [ ] Fresh install → sign up with email OTP → OTP arrives → lands on home
- [ ] Sign up with Google → lands on home
- [ ] Browse home, open a restaurant, add items, cart totals match the menu
- [ ] Apply a coupon; apply an invalid one and read the refusal
- [ ] Add a delivery address, pick it at checkout
- [ ] Checkout shows **UPI only** — no cash option anywhere
- [ ] Place an order → vendor tablet shows it within seconds
- [ ] Vendor accepts with a prep time → customer's ETA updates
- [ ] Rider offered the job → accepts → pickup code → delivery OTP at the door
- [ ] Order completes; invoice PDF opens and the tax lines add up
- [ ] Rate the order; the restaurant's rating moves
- [ ] Cancel a different order before accept; refund path recorded
- [ ] Notifications: push arrives with the app killed, and opens the right screen
- [ ] Account → delete account → confirm → signed out, cannot sign back in
- [ ] Reinstall → sign up again with the same email works
- [ ] Airplane mode mid-browse: no white screen of death

---

## Console checklist — things only you can do

- [ ] Account type confirmed (L0)
- [ ] App created in the console, package `com.siteonlab.zopiqnow`
- [ ] Play App Signing enrolled, upload key registered
- [ ] Store listing complete (R3)
- [ ] Content rating questionnaire
- [ ] Data safety form (from L5)
- [ ] Privacy policy URL live and reachable
- [ ] Target audience and content
- [ ] App access — **test account credentials for the reviewer**
- [ ] Ads declaration (no ads)
- [ ] Government / financial app declarations: food delivery is neither, but the
      payments question gets asked — answer it consistently with UPI-via-Razorpay
- [ ] Countries: India
- [ ] Release notes

---

## How we work until 5 August

- **One commit per item**, same convention as the audit queue:
  `fix(<area>): <lowercase sentence> (launch <ID>)` for items originating here,
  and the existing `(audit <ID>)` form when the item is an audit finding.
- **Ship-first triage.** If something is not on this list, it does not get
  fixed before launch — it gets written down. Tell me and I will add it to
  `AUDIT_CHECKLIST.md` rather than doing it.
- **No refactors.** Not one. Every change is the smallest change that closes
  its item.
- **The release build is the build we test.** R8 changes the binary; a feature
  that works in debug has not been tested.
- **An RPC is proven over HTTP, not in `psql`.** Call it against the real URL
  with a real user's access token. As `postgres` you bypass `pg_safeupdate`, RLS
  and every grant — which is how a `where`-less `update` shipped and stopped the
  product taking orders for three days.
- **Verify in a clean worktree, never in the working tree.** `git worktree add`
  a detached checkout of the commit, run analyze and the suites there, remove it.
  The working tree passing proves nothing about what you committed — that is
  exactly how `main` came to be unbuildable without anyone noticing.
- After each session I will report what closed, what did not, and what that does
  to the date. If the date stops being reachable you will hear it from me on the
  day I know, not on 5 August.
