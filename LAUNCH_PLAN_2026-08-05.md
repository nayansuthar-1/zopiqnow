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
| L2 | **In-app account deletion** — an Account screen entry, a confirmation that says what is kept and why, and the RPC behind it. Orders cannot simply vanish (tax records, settlements owed to restaurants), so the account is deleted and its orders are anonymised — migration 0081. | Me | 4 h |
| L3 | **Web account-deletion page.** Play requires a deletion route reachable *without* installing the app. A page on the same host as the policy. | Me + you to host | 1 h |
| L4 | **Privacy policy + terms**, written against what the app actually collects: phone, email, name, delivery addresses, coarse and precise location, profile photo, device push token. I will write them from the schema, not from a template. | Me | 2 h |
| L5 | **Data-safety answers** — the exact table to type into the console, derived from the same audit of what is collected. | Me | 1 h |
| L6 | In-app links to policy and terms from the Account screen, and consent wording at sign-up. | Me | 1 h |

### 2–3 Aug — the app itself

| # | What | Who | Time |
|---|---|---|---|
| C1 | **Remove cash on delivery from checkout.** UPI becomes the only method offered. Server and vendor/rider apps keep the ability to handle a cash order — that is data that already exists — but no new one can be created. | Me | 1 h |
| C2 | **Razorpay adapter + server-side signature verification + the mock lockout** described above. Ends with everything ready for keys. | Me | 5 h |
| C3 | **Crash reporting** (audit OBS-001) — Crashlytics in the customer app, and in vendor and rider if time allows. Launching without it means your first bug report is a one-star review. This is the highest-value non-gate item on the list. | Me | 3 h |
| C4 | **Idempotency on `place_order`** (audit CUS-005). A double-tap or a retry on a flaky connection currently places two orders. With prepaid UPI that is two charges. | Me | 2 h |
| C5 | **Hide the dead Account tiles** (audit UX-001). Five tiles currently raise a "coming soon" snackbar. Not a policy gate; it is what makes an app feel abandoned on first open. Hiding them is minutes — building them is not on this plan. | Me | 1 h |
| C6 | **Delivery OTP no longer shown unconditionally** on the tracking card (audit CUS-015). It is the proof-of-delivery code; it should appear when the rider is at the door, not from the moment the order is placed. | Me | 1 h |
| C7 | **`ola-static` gets caller authentication** (audit API-002). It proxies your Ola Maps key with no auth — anyone who finds the URL spends your quota. | Me | 2 h |
| C8 | **Release keystores for vendor and rider**, so the closed-track builds are real builds. Customer already has one. | Me + you for the passwords | 1 h |

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
- After each session I will report what closed, what did not, and what that does
  to the date. If the date stops being reachable you will hear it from me on the
  day I know, not on 5 August.
