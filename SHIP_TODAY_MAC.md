# Ship day — the 3-hour runbook for the Mac

**Written 2026-08-20 on the Windows box, for the Claude session on the Mac.**
Scope decided by the owner today: **customer app only, both stores.** Rider and
Partner stay where they are.

`IOS_RELEASE_RUNBOOK.md` is the reference; this file is the *order of work for
today*, cut down to what actually blocks a submission and split into lanes that
run at the same time. Where the two disagree about status, the Mac wins — see
that file's "Corrections from 2026-08-20".

---

## 0. The one thing that decides today

**There are no Razorpay keys, and that is not a payments problem — it is a
review problem.**

`paymentGatewayProvider` binds `RazorpayPaymentGateway` with `MockPaymentGateway`
behind it. The server answers `configured: false` while
`RAZORPAY_KEY_ID`/`RAZORPAY_KEY_SECRET` are unset as Supabase function secrets,
so the fallback is what a reviewer reaches. It draws a sheet that says, in the
build:

> **Test gateway. No money moves — the real Razorpay sheet takes over once the
> keys are in.**

Apple rejects placeholder and test content under **Guideline 2.1 (App
Completeness)**, and `IOS_APP_STORE_LISTING.md` §3 promises "Checkout runs
through Razorpay." Submitting on top of that sheet is asking for a rejection and
a second review cycle.

The same fact governs Android: publishing to **production** with the mock behind
checkout means anyone can order food for free. Applying for production access
today is right and costs nothing; *publishing* the production release is not,
until keys are in and `require_verified_payment` is armed.

**So Lane A1 — get Razorpay live keys — is the critical path, and everything
else in this file is designed to finish before it does.**

If keys cannot be had today: do every other step, push the build to
**TestFlight** (reversible, no App Review), and hold the review submission and
the Android production release. That is a good day's work and loses nothing.

---

## 1. The three lanes

| | Lane A — the owner (GUI, accounts) | Lane B — Claude on the Mac (build, files) |
|---|---|---|
| T+0:00 | **A1** Razorpay signup, instant activation, live keys | **B1** Pull, resolve, commit the pending pubspec |
| T+0:10 | **A2** Supabase: fixed-OTP demo account | **B2** Screenshots on a 6.9" simulator |
| T+0:30 | **A3** Play Console: apply for production access | **B2** continues |
| T+1:00 | **A4** App Store Connect: paste the metadata | **B3** Set the Razorpay secrets, arm the gate |
| T+1:15 | **A5** App Privacy questionnaire | **B4** `ship_ios.mjs customer` to TestFlight |
| T+2:15 | **A6** Upload screenshots, attach build, **submit** | **B5** Write back what happened |

Lane A and Lane B never wait on each other except at T+1:00 (B3 needs A1's keys)
and T+2:15 (A6 needs B4's build).

---

## 2. Lane A — the owner

### A1. Razorpay live keys — do this first, everything waits on it

1. https://dashboard.razorpay.com — sign up as **Hybrid Monks LLP** (the legal
   entity in the listing, and on the invoices the app already generates).
2. Take **instant activation** if offered — Razorpay grants a capped live
   account before full KYC, and a capped live account is a *real* Razorpay sheet,
   which is all App Review needs.
3. Settings → **API Keys** → *Generate Live Key*. You get the secret **once**.
4. Hand both to the Mac session, or set them yourself (B3 has the commands).

⚠️ **Test-mode keys (`rzp_test_…`) are a trap here.** They remove the placeholder
sheet, so the App Review problem looks solved — and they also silently make every
*real* order free, on Android builds that are already on phones. Live keys or the
mock; not test keys.

### A2. The fixed-OTP demo account (5 minutes, blocks submission)

The reviewer cannot receive an email OTP. Per `IOS_APP_STORE_LISTING.md` §4:

1. Supabase Dashboard → **Authentication → Sign In / Providers → Email → Test
   OTPs**. Map one throwaway address to a fixed six-digit code. **Not `123456`.**
2. Tell the Mac session the address and code — B2 signs in with it on the
   simulator, which both proves the path and produces the screenshots from a
   populated account.
3. That account needs a **saved delivery address in Falna**, or the reviewer
   lands on an empty feed and gets rejected for incompleteness. B2 does this.

### A3. Play Console — apply for production access (15 minutes)

The customer app reached closed testing **2026-08-06**; today is day 14, so the
12-testers-for-14-continuous-days gate should now be satisfied.

1. Play Console → the customer app → **Testing → Closed testing** → check the
   tester count has held at 12+ for the whole window.
2. **Dashboard → Apply for production access.** Fill in the questionnaire.
3. **Do not create the production release yet.** Approval takes days; the release
   itself waits for A1's keys and B3's arming. Applying is free and starts a
   clock you want started.

Vendor and rider reached closed testing 2026-08-12 — their window closes around
08-26. Nothing to do for them today.

### A4. App Store Connect metadata (~30 minutes, pure paste)

Everything is written out in **`IOS_APP_STORE_LISTING.md`**. Paste, do not
retype. In order: §2 the record fields and the four URLs, §3 name / subtitle /
promotional text / keywords / description / What's New, §4 App Review
Information — sign-in required = **Yes**, the A2 address as *User name*, the
fixed code as *Password*, and the review notes verbatim.

The PAYMENT paragraph in those notes is written for a live Razorpay. If A1 did
not land, you are not submitting today (see §0), so the question does not arise.

### A5. App Privacy (~15 minutes)

`IOS_APP_STORE_LISTING.md` §5 is the full answer key: three overview answers
(collects data **yes**, tracking **no**, third-party advertising **no**), fifteen
data types, all *collected / linked / not used for tracking*, and an explicit
"do NOT declare" list. Work down it row by row rather than from memory — the
reasoning for each is in that file if a question is challenged.

### A6. Screenshots, build, submit

1. Media Manager → upload the PNGs Lane B produced, in the order §6 lists.
2. **Build** → select the build B4 uploaded (it appears a few minutes after
   processing finishes).
3. Export compliance is already answered — `ITSAppUsesNonExemptEncryption` is
   `false` in the plist.
4. **Add for Review → Submit.**

---

## 3. Lane B — Claude on the Mac

### B1. Pull and clear the tree (5 minutes)

```bash
cd /path/to/zopiqnow
git pull
git status --short          # must be clean before anything is built
flutter --version           # expect 3.44.8 — do NOT change it
flutter pub get             # NOT upgrade
```

The pubspec now reads `1.0.0+17`, committed today — it had been left dirty on the
Windows box after the hand-upload of build 17. **The tree must be clean before
you build**: the standing rule is that nothing ships from a dirty tree, and
`ship_ios.mjs` stages only the pubspec, so anything else left dirty is invisible
in the release commit and still reaches users.

`ship_ios.mjs` asks Apple for the highest build it already holds and takes
`max(pubspec, Apple) + 1`, so the number sorts itself out — Apple already has 16
and 17.

### B2. Screenshots, from the simulator (~40 minutes, no device needed)

Apple requires **6.9"** (1290×2796 or 1320×2868). Use an **iPhone 16 Pro Max**
simulator. Simulator captures are accepted as long as they show the real app.

Follow the `IOS_RELEASE_RUNBOOK.md` §A4 recipe exactly — and heed its trap: **a
running app clobbers `SharedPreferences` on exit**, so uninstall, then seed, then
launch, and read the town off the screenshot header before trusting it.

Two changes from that recipe for today:

- Sign in with the **A2 demo account** rather than browsing signed-out. The
  screenshots must match what the reviewer sees, and the cart and Gifts shots
  need a session anyway.
- Save the demo account's **Falna delivery address** while you are signed in.
  That is A2 step 3, and doing it here means it is done on the same account the
  reviewer will use.

Capture five, in this order (`IOS_APP_STORE_LISTING.md` §6, minus the tracking
shot — it needs a live rider and there is no time for that today):

1. Restaurant feed with the address set
2. A restaurant page with its photo strip and menu
3. The cart, showing the price breakdown
4. The Gifts tab
5. Veg mode on, filtering the feed

⚠️ **Do not screenshot the payment sheet.** If the mock is still behind checkout,
that image is a rejection in itself.

Write the PNGs to `apps/customer/store/ios/` and say which is which.

### B3. Razorpay secrets and the gate (10 minutes, needs A1)

Only once **live** keys are in hand:

```bash
supabase login                                    # interactive — the human
supabase link --project-ref ofjjuzrxnksbyglzwaah
supabase secrets set RAZORPAY_KEY_ID=... RAZORPAY_KEY_SECRET=...
supabase functions deploy razorpay-order
supabase functions deploy razorpay-verify
```

Then confirm the server flipped — `razorpay-order` must stop answering
`configured: false` — **before** arming the trigger:

```sql
update public.payment_settings set require_verified_payment = true;
```

**Order matters and the failure is an outage.** Arming the gate while the
functions still answer `configured:false` means every order in flight is refused
by the 0085 trigger, on Android too, on builds already installed. Verify the
function first, arm second.

Re-check the mock is gone: reach the payment sheet on the simulator and confirm
it is Razorpay's, not the sheet with the "Test gateway" banner.

### B4. Build and upload to TestFlight (~30 minutes, mostly waiting)

```bash
node tool/ship_ios.mjs --check      # token accepted? record found? group ids?
node tool/ship_ios.mjs customer
```

That bumps, builds the `.ipa`, uploads via `altool`, waits for Apple to finish
processing, and commits the bump **after** Apple has the binary. It deliberately
does **not** submit for review — that is A6, and it is the owner's call.

If `--check` reports a missing `ExportOptions.plist`, it lives at
`apps/customer/ios/ExportOptions.plist` and is untracked on this Mac only — it is
not in git, so do not expect `git pull` to bring it.

**Not required today**, despite being in the runbook: the APNs `.p8`, the
`send-notification` redeploy, and the Live Activity target. Push being unproven
on iOS does not block a submission, and Phase C is explicitly cut from v1.

### B5. Write back

Per `IOS_RELEASE_RUNBOOK.md` §7 — update `IOS_HANDOVER.md` §0 and the status
table in the runbook with what actually happened, evidence being real command
output rather than "it worked". Note anything in *this* file that turned out to
be wrong; it was written by a session that cannot compile a line of it.

---

## 4. What today cannot produce, so nobody waits for it

- **An app live on the App Store.** Review is Apple's clock — typically under 24
  hours for a first submission, sometimes days. Today ends at *submitted*.
- **An app live on Play production.** Production *access* is an application, and
  Google takes days to answer it. Today ends at *applied*.
- **Proof that push works on iOS.** No device, no APNs key. Unproven, not broken.
- **Proof that UPI works on an iPhone.** A simulator has no UPI app to hand the
  intent to. This stays the largest untested path in the product, and the first
  thing to do the day a real iPhone is in reach.
