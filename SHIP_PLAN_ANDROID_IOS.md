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

> **Phase 1 is closed as of 3 August**, S1–S9, migrations 0087 and 0089–0093.
> **One item is not finished and is not mine: S5** — the payment gate cannot be
> armed until the Razorpay merchant keys exist (G3), and it ends with one real ₹1
> payment on a device on each platform. Everything else in this phase is done and
> was verified against the live database.
>
> **Two standing checks must return zero rows before every release.** They are in
> the footers of `0087_a_revoke_that_did_nothing.sql` (no function executable by
> PUBLIC) and `0089_a_grant_nobody_asked_for.sql` (no write grant a policy does
> not scope). Both return zero today.

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
- [x] **S4 — The money path cannot be talked into a discount.** ✅ **Closed 3 Aug
      — migration 0089.** The arithmetic is clean and was proven by attacking it;
      what was wrong was one layer underneath it. See below.
- [ ] **S5 — Arm the payment gate.** `update public.payment_settings set
      require_verified_payment = true;` the moment `RAZORPAY_KEY_ID` /
      `RAZORPAY_KEY_SECRET` are set as function secrets (G3). Until then, a
      release build already refuses to settle a mock payment — that lock stays.
      **Ends with one real ₹1 payment on a real device, on each platform**; the
      signature path has never run against Razorpay, only against a known-good
      vector.
- [x] **S6 — Rate-limit what costs money or sends mail.** ✅ **Closed 3 Aug —
      migration 0090.** Three limits built and one deliberately not built. See
      below.
- [x] **S7 — Edge functions: real auth, not `verify_jwt`.** ✅ **Closed 3 Aug —
      migration 0091.** The premise was right and its stated mechanism was wrong;
      the functions themselves came out clean, and the finding was a key sitting
      somewhere nobody thinks to look. See below.
- [x] **S8 — Privileged actions leave a trace.** ✅ **Closed 3 Aug — migration
      0092.** `admin_actions`, append-only and meant literally, fed by 14
      triggers on 11 tables. **No existing function was rewritten.** See below.
- [x] **S9 — The rider KYC gate is server-side.** ✅ **Closed 3 Aug — migration
      0093.** The gate is sound and needed no change; the two things wrong were
      beside it. See below. **Phase 1 is now closed.**

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

### What S4 found — the pricing holds, the privileges did not

**The arithmetic is right, and it was attacked rather than read.** Ten cases run
against the live `place_order` as role `authenticated` with a forged subject,
each in a rolled-back savepoint. A cart of 2 × ₹320 charges ₹672 — ₹640
subtotal, free delivery over ₹500, 5% GST — and it charges exactly that when the
request also carries `price: 1`, `unit_price: 1`, `line_total: 1`, `discount:
600`, `taxable_value: 1` and `gst_rate_bps: 0`. **Every one of those keys is
ignored**, because the function reads only `menu_item_id`, `quantity` and
`option_ids` from the request and prices everything else out of `menu_items`,
`menu_options` and `coupons`. Refused, each with its own sentence: a negative
quantity, an item from another restaurant, an invented option id, an option
borrowed from a different dish, a coupon that does not exist, and a UPI order
with no payment id. A quantity chosen to overflow the line total raises
`integer out of range` — Postgres does not wrap, so there is no negative total
behind it.

The Razorpay amount is client-supplied *by design* and is not the hole it looks
like: `place_order` reprices the cart in Postgres, and 0085's trigger refuses any
intent worth less than the order's own total. Understating it buys a refusal.
Overstating it is the customer's own money and a refund. The refund path never
takes an amount from a client either — the automatic one uses `orders.total`, and
`refund_within_the_order` caps every writer, admin included, at what the order
was worth.

**The real finding is one layer down.** Twenty-eight tables — `orders`,
`order_items`, `restaurants`, `settlements`, `platform_admins`, `user_blocks`
among them — carried INSERT, UPDATE, DELETE and TRUNCATE for **`anon`**, the role
the shipped key resolves to. Nothing was exploitable: all of them have RLS on and
no write policy, so the writes matched zero rows. But that made RLS the *only*
guard, and the difference showed in the HTTP replies — a POST to
`/rest/v1/payment_intents` was refused because the privilege does not exist, and
a PATCH to `/rest/v1/orders` was refused because a policy was doing a privilege's
job. One `for all using (true)` written in a hurry is the distance between them.

**TRUNCATE was not even that well covered.** RLS governs SELECT, INSERT, UPDATE,
DELETE and MERGE. It does not govern TRUNCATE — that is checked against the
privilege alone. What stopped it was that PostgREST exposes no TRUNCATE verb,
which is an accident of the client rather than a decision of ours.

**Source, not symptom.** Two `pg_default_acl` rows grant `arwdDxtm` on *every new
table* in `public` to `anon` and `authenticated` — so every table any migration
ever created arrived writable by anonymous callers. 0089 revokes the excess and
**fixes the `postgres` default**, so this is a default corrected rather than a
list swept. Only `addresses`, `favourites` and `menu_items` keep write
privileges, for `authenticated` only; they are the only three tables written
directly by a client rather than through an RPC, confirmed by reading every
`.from(...).insert/update/delete` in all three apps and the console.

Verified after applying: both verification queries return zero rows, the
ambiguous `204`s are now `401 42501`, and reads still answer `200`.

> **The rule, and it is the table-shaped twin of 0087's:** a migration that
> creates a table must grant it nothing it does not need. The verification query
> in the footer of `0089_a_grant_nobody_asked_for.sql` **must return zero rows
> before each release**, alongside 0087's.

### What S6 built — three limits, and one that would have been theatre

Each limit **counts the rows the action itself already writes** rather than
keeping a bucket table of its own. A counter that is separate from the thing it
counts is a counter that can drift from it; this one cannot, because it *is* the
thing it counts. No new table, and `orders_user_idx` already indexed the only
count that will ever be hot.

| | Limit | Where it lives |
|---|---|---|
| **Order placement** | 10 per hour per customer | `before insert` trigger on `orders` |
| **Broadcast** | 6 per hour per admin | beside the duplicate guard in `admin_send_broadcast` |
| **Chat** | 20 per side per delivery | beside the 3-second guard in `send_order_message` |
| **OTP send** | — | GoTrue's, not ours. Not built, on purpose |

**Order placement is a trigger, not a check inside `place_order`** — the same
shape as 0084's cash refusal, 0085's payment gate and 0088's blocked user,
because the rule belongs to the table and then every path is covered rather than
the one path we remembered. The name was chosen so it fires *after* the blocked
and cash refusals (a blocked customer should read that they are blocked, not that
they are in a hurry) and *before* the payment gate, so a refused order never
consumes a payment intent. **Cancelled and rejected orders still count** — each
one rang a kitchen, and a limit that resets when you cancel is not a limit. Ten
an hour is generous for a household and cheap for us; with the payment gate
disarmed (S5), placing an order costs a stranger nothing and costs a cook a
ticket.

**The broadcast is the most expensive call in the system** — one `notifications`
row, and one push, per registered device. The only thing limiting it was a
five-minute refusal of the *exact same* message, which stops a double submit and
does nothing about a hundred different ones.

**Push is limited at its producers, because it has no other door.** Nothing can
write a `notifications` row from outside: RLS is on, there is no write policy,
and after 0089 no write privilege either, so every row comes from a definer
function. The edge function is already gated on `NOTIFY_WEBHOOK_SECRET` and
re-reads the row from the table, so it cannot be made to invent one. That leaves
three producers — order events, broadcasts, and the chat — and all three are now
capped.

**OTP is the one that was not built, and that is the finding.** No trigger,
policy or function in this database sits on that path; the endpoint is GoTrue's.
What governs it is server configuration and it is already set —
`smtp_max_frequency` 45s per address, `rate_limit_otp` and `rate_limit_email_sent`
at 200/hour. **`rate_limit_verify` is still 30 and still caps sign-ins: G13.**
The abuse a throughput cap cannot answer is the distributed one, and hCaptcha is
that control; it is recorded in G13 as post-launch. Writing something in SQL here
would have made this file look more complete than the system is.

**Verified by exercising every boundary, in rolled-back transactions:** ten
orders placed and the eleventh refused, with a second customer unaffected;
a broadcast let through at five and refused at six, with a second admin
unaffected and the refusal landing *before* any recipient row is written; the
twentieth chat line sent, the twenty-first refused, and the customer's side
untouched by the rider's twenty. The two release checks (0087, 0089) still return
zero rows.

> **A note on testing time-based limits here:** `now()` is the *transaction*
> timestamp and does not advance inside one, so `pg_sleep` cannot clear a
> throttle. The 21st chat line first came back refused by the old 3-second guard
> rather than the new ceiling, which read as a pass and was not one. Backdating
> the fixtures is the only way to test the limit you actually added.

**Found on the way, and it is S7's:** the `push_on_notification_insert` webhook
stores a **`service_role` JWT in plaintext** in its trigger definition, readable
from `pg_get_triggerdef` by anything that can read the catalog. `send-notification`
is deployed `--no-verify-jwt` and authenticates on `x-notify-secret` instead, so
**that header buys nothing and can simply go.** Logged as `SEC-010`.

### What S7 found — the functions were fine, the catalogue was not

**Correction to this item's own premise, because someone will reason from it
later.** S7 said `verify_jwt` is weak because "the anon key is such a JWT". The
conclusion is right; the mechanism is not. **This project's shipped key is not a
JWT at all** — it is `sb_publishable_…`, the new-format publishable key, one
segment, no claims. The gateway accepts it anyway: `razorpay-order` answers
**`200`** to a caller carrying nothing but the key out of the APK, while the same
request with no header gets `401 UNAUTHORIZED_NO_AUTH_HEADER` and with a
malformed bearer gets `401 UNAUTHORIZED_INVALID_JWT_FORMAT`. So the rule stands
and is worth restating properly: **the gateway proves the caller has the key
every user has. It is not authentication, and only the handler's own check is.**

**All four handlers do have one, and they are right.** Probed as a stranger — no
header, the shipped key, and a garbage bearer:

| | As a stranger | Verdict |
|---|---|---|
| `razorpay-order` | `200 {"configured":false}` | authenticates properly *once configured* — `getUser(token)`, never a user id from the body |
| `razorpay-verify` | `503 not configured` | same, plus constant-time HMAC and an intent matched on caller as well as order |
| `send-notification` | `403 Forbidden` | fails closed on `x-notify-secret`; the gateway is not even consulted |
| `ola-static` | `404` | **gone.** Audit API-002 recorded the delete as still owed; it is done |
| `send-order-push` | `404` | gone, as G7 recorded |

And the load-bearing assumption underneath the two Razorpay handlers was checked
rather than believed: `GET /auth/v1/user` with the shipped key returns **`401`**,
so `getUser()` cannot be satisfied by it.

**The real finding was SEC-010, and it was not in a function at all.** The
notifications webhook carried `Authorization: Bearer <service_role JWT>` in its
trigger arguments. `pg_trigger` is world-readable and `pg_get_triggerdef` is
executable by PUBLIC, so anything that can read the catalogue could read the one
key that bypasses RLS entirely — a logical backup, a dashboard user, a read-only
foothold. Not reachable through PostgREST, which exposes no catalogue, so it is
an **escalation path rather than an open door** — and still the most valuable
string in the project stored where it did not need to be.

**And it bought nothing.** Proven before touching it: a POST to
`send-notification` with *no* Authorization header returns `403` from the
handler's own secret check, not `401` from the gateway. The gateway was never
looking. 0091 removes the header **by reading the existing headers and deleting
one key** — restating them would have put `x-notify-secret` into a migration file
and then into git, which is exactly how SEC-007 happened. The secret never left
the database.

**Verified end to end, without waking anybody's phone:** one notification
addressed to a customer id with no registered devices, committed so the webhook
actually fired. `net._http_response` recorded **`200 "No devices"`** — past the
secret check, past the row re-read, into the device query. Push is intact and the
key is out of the catalogue. Probe row deleted.

**The sweep, so this is a class and not an instance:** there is exactly one other
`http_request` trigger (none), and one function that touches a secret —
`process_order_routes`, which reads the Ola key from `vault.decrypted_secrets` at
run time. **The project already knows the right pattern**; the webhook was
created through the dashboard UI, which inlines the key. `net.http_request_queue`
retains nothing (checked: zero rows), and the 44 retained responses carry route
JSON and no credentials.

**Also closed here: a payment intent is a real Razorpay order, and nothing
bounded it.** `razorpay-order` authenticates the caller properly but a signed-in
customer could call it without limit, each call creating an order at Razorpay and
a row here — S6's shape exactly, latent only because the keys are unset, and
therefore arriving *the same day payments do*. Now 30/hour per customer, in the
database. Deliberately well above 0090's ten orders an hour: a customer whose UPI
app fails will retry, and a refused retry is worse than a refused first attempt.

**Two things logged rather than done, both tied to G3.** Both are edge-function
source changes, and changing that source without deploying it is how the repo and
the live system drift — which this project has been bitten by four times. The
keys must be set and the functions redeployed for S5 anyway, so both belong to
that same run:

- The `{configured:false}` / `503` early returns sit *before* the auth check, so
  an unauthenticated caller learns whether payments are configured. Trivial, and
  it should still be the other way round.
- `razorpay-order` creates the Razorpay order *before* inserting the intent, so a
  rate refusal leaves an unused order at Razorpay and returns a 500. That is the
  safe direction — the alternative is a payment that can never become an order —
  but checking the ceiling before the Razorpay call is tidier.

### What S8 built — a trail that cannot be forgotten or edited

**Triggers on tables, not a log line inside each admin function.** There are 72
`admin_*` functions and roughly 25 are destructive. Instrumenting each means
rewriting 25 working bodies — 25 chances to mistranscribe — and it records only
what we *remembered* to instrument: the next migration that deletes a row
directly, or a console screen that grows a new delete, would be silently outside
the trail. A trigger is attached to the thing being protected rather than to the
path that happens to reach it. **This migration rewrites no existing function.**

| Covered | What |
|---|---|
| Every `DELETE` | orders, restaurants, menu_items, coupons, hero_slides, platform_admins, restaurant_staff, delivery_partners |
| Privilege | `INSERT` into platform_admins — adding an admin makes more of the power this table watches |
| Money & livelihood | refunds, settlements, rider_payouts on `status` change; delivery_partners, restaurants on `is_active` change |

The `when` clause does the filtering, so an ordinary edit writes nothing —
verified: an `update restaurants set eta_minutes = eta_minutes` leaves the trail
at the same length. **Deliberately not covered:** ordinary order-lifecycle
transitions, menu edits short of deletion, and reads. An audit log that records
everything is one nobody reads.

**The actor is whoever the request belonged to**, from the JWT, lower-cased. A
deletion run by a migration or a cron job has no JWT and is recorded as
`system` — a true and useful answer rather than a null. Verified both ways.

**"Append-only" is meant literally.** Grants alone would leave `postgres` and
`service_role` able to rewrite history, so a statement-level trigger refuses
`UPDATE` and `DELETE` outright. Proven by trying it *as `postgres`*: both come
back refused. The only way to alter this table is to deliberately disable a
trigger, which nobody does by accident.

**The deleted row is recoverable from the trail.** `detail` holds the whole old
row — a coupon deleted at 50 off reads back as 50 off. For updates it holds
`before` and `after`.

**Read through `admin_list_actions` and nowhere else** — RLS on with no policy,
the `user_blocks` shape from 0088. A signed-in stranger calling it gets *"You are
not a Zopiqnow admin."*

**Two things worth recording beyond the feature:**

1. **0089's fixed default proved itself.** `admin_actions` is the first table
   created since, and it arrived with **no INSERT, UPDATE, DELETE or TRUNCATE**
   for `anon` or `authenticated`. That is the live confirmation the migration
   could only assert.
2. **It still arrived with `SELECT`,** which is right for most tables and wrong
   for this one — it holds snapshots of deleted rows, the most personal data in
   the schema gathered in one place. S4's lesson was that RLS should not be the
   only guard, so `SELECT` is revoked from `anon` and `authenticated` on
   `admin_actions` **and on `user_blocks`**. Safe because the console makes no
   direct table reads at all: its only `.from(...)` calls are Storage buckets and
   every table access is an RPC.

**Still one flat admin role with no MFA (SEC-003).** That is unchanged and still
deferred until a second admin account exists. What S8 buys is that when it
matters, the question "who did this, and what was in the row before it went" has
an answer.

### What S9 found — the gate holds; a vouch left no trace

**The gate is in the database, confirmed against the live function bodies rather
than the migration that wrote them** — which matters, because 0083 and the B3
dispatch work both replaced functions in this area after 0080, and a
`create or replace` that quietly dropped the guard is exactly this repo's history.
All five still call it: `set_rider_online`, `available_deliveries`,
`claim_delivery` and `accept_offer` via `rider_work_block`, and `offer_delivery`
via `rider_is_verified` — the boolean form, because the dispatcher filters whom
to offer to rather than raising at them.

**Ten document states, all five paths, every one correct.** No `rider_legal` row,
pending, rejected, verified-and-current, licence expired, insurance expired,
expiring *today*, a cyclist with expired papers, an override, and a lapsed
override. **An expired document blocks exactly as a missing one does** — and
better, because it names the document and the date it went. Expiry is recomputed
against `current_date` on every call, never stored, so a licence lapses at
midnight with nothing to run. The boundary agrees between the two functions:
expiring *today* still works.

**A cyclist is exempt from licence and insurance by design** — they are verified
on identity alone. That is correct and worth knowing it is deliberate.

**The finding: an override is the most powerful switch in the product and nothing
recorded it.** `rider_override_active` passes when `override_reason` is set and
`override_until` is in the future **or null** — and a null is permanent. It
defeats every other condition at once: a rider whose documents were *rejected*,
whose licence expired 400 days ago and whose insurance lapsed with it passed all
five gates. Proven by building that exact row. It is a legitimate power — a
partner whose papers are genuinely with the RTO should not lose a week's earnings
to a queue — but it is the one action that puts an unverified stranger at a
customer's door, and the only trace was the row itself, which the next override
overwrites. `rider_legal` now feeds 0092's trail on **every** insert and update:
one row per rider, every write a KYC decision, no noise to filter.

**And a wording defect worth the four characters.** The rejected message
concatenated the admin's typed reason with a fixed sentence, so a reason without
a full stop produced *"The licence photo was unreadable Call Zopiqnow support to
sort it out."* Two sentences run together, read by somebody who has just been
stopped from earning. Now trimmed and punctuated once, so a reason typed with or
without a stop both read correctly.

> **A product decision left for you, deliberately not made in a migration:**
> should `override_until = null` keep meaning *permanent*? Forcing every vouch to
> expire — 30 days, say — would mean no rider is ever indefinitely unverified,
> and would also mean somebody must remember to renew it or a working partner
> stops earning. That is a judgement about people's livelihoods, not a schema
> change. It is now at least **visible**, which it was not before.

**Two things noted and deliberately not fixed**, both written into
`AUDIT_CHECKLIST.md` rather than done here:

- `place_order` creates a temp table `_lines … on commit drop`, so **it cannot be
  called twice inside one transaction** — the second call dies on `relation
  "_lines" already exists`. Harmless in production, where every PostgREST RPC is
  its own transaction, and it is why the probe above needs a savepoint per case.
- `REFERENCES` and `TRIGGER` are still granted to `anon` on those tables. Neither
  is reachable through PostgREST, which issues no DDL, so they are untidiness
  rather than exposure.

**The one claim not proven the way this plan demands.** The pricing cases ran in
`psql` as role `authenticated`, not over HTTP with a real user token — minting one
needs either a `service_role` key (absent from `.env`) or a write to `auth.users`,
and both attempts were refused by the permission classifier. The gap that rule
exists to catch is `pg_safeupdate`, which is preloaded for `authenticator` and so
is live for every real request and absent from psql; `LOAD 'safeupdate'` is
blocked by supautils, so it could not be reproduced. It **cannot fire here**: it
only refuses a `WHERE`-less UPDATE, and all three UPDATEs in the live function
carry one (`where true`, `where a.seq = l.seq`, `where r.seq = l.seq`). The anon
half *was* done over HTTP — `place_order` answers `401 permission denied for
function` to the shipped key. **Ten minutes with a real signed-in device closes
the rest, and it is folded into Phase 5.**

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
- [x] **A2 — Release keystores for vendor and rider** (audit REL-001, launch C8).
      ✅ **Closed 4 Aug.** Both generated to the customer keystore's own
      conventions rather than to new ones — `SHA256withRSA`, 2048-bit, 10000-day
      validity, the same `OU=SiteOnLab, O=SiteOnLab, L=Surat, ST=Gujarat, C=IN`,
      with the CN distinguishing the three. Aliases `zopiqvendor` and
      `zopiqrider`; 32-character random passwords.

      Both build files now carry the customer's pattern verbatim, including the
      part that matters most for a repo more than one person clones: **a missing
      `key.properties` falls back to debug signing rather than failing the
      build.** Such a build is not publishable, which is the honest consequence.
      The `TODO: Replace debug signing` in each is gone because it is done.

      **Proven by the certificate, not by the build succeeding.** Both AABs were
      built and the cert *inside the bundle* read back with
      `keytool -printcert -jarfile`: vendor `FF:60:1D:6E:…`, rider
      `43:37:B4:B4:…`, each matching its own keystore's SHA-256 exactly. A
      bundle that builds proves nothing about *which* key signed it — a debug
      fallback builds just as happily.

      **Verified ignored before anything was committed:** `git status --ignored`
      reports all four files (`key.properties` × 2, `.jks` × 2) as `!!`. Nothing
      secret is in this repository.

      > **G9 is what is left, and it is yours.** The passwords exist in
      > `apps/<app>/android/key.properties` on one laptop. Copy those two
      > passwords **and** the two `.jks` files off it. **A lost upload key is a
      > new app listing** — there is no recovery, from anyone.
- [x] **A3 — R8 on, and proven.** ✅ **Closed 3 Aug — and the finding is which
      app it was off in.** Customer and vendor already had `isMinifyEnabled`;
      **the rider had neither it nor a keep file**, so a third of what ships was
      a binary R8 had never touched — exactly the "different binary from every
      build tested so far" this item was written about. Now on, with its own
      `proguard-rules.pro`.

      **The rider's keep file is deliberately not a copy of the other two.** Both
      carry a Razorpay block; `razorpay_flutter` is a **customer-only**
      dependency and a rider never takes a payment. Firebase, geolocator and
      `google_maps_flutter` ship consumer rules inside their AARs, so nothing is
      restated. *(Noted, not fixed: the **vendor's** file carries the same
      Razorpay block for a dependency it does not have either. A keep on absent
      classes is a no-op, so it is misleading rather than harmful.)*

      **Proven rather than switched on.** `assembleRelease` succeeds in 679s with
      no missing-class warnings, and R8 demonstrably ran: a 17 MB mapping, 2,606
      classes renamed, 437 removed outright, plus the resource-shrinker report.
      The keeps held **both ways** — every `io.flutter.*` entry maps to itself
      and none is renamed short — and geolocator (33), Maps (87), Firebase (288)
      and the Flutter plugins (357) all survive. All three apps now carry the
      same evidence: customer 4,276 renamed / 609 removed, vendor 2,221 / 354,
      rider 2,606 / 437.

      > **What this does not prove, and the reason A3 is not the end of it:** a
      > minified build that *compiles* has not *exercised* a reflection path.
      > Razorpay's `@JavascriptInterface` callbacks and the Live Activity plugin
      > fail at runtime or not at all. That is a device smoke test — **A5 and
      > Phase 5**, on the release build, which is now the only build worth
      > testing.
- [x] **A4 — Manifest and permission minimisation.** ✅ **Closed 3 Aug — no code
      change, and that is the finding.** The register is in
      `PLAY_DATA_SAFETY.md`; read it before answering D3.

      **What a manifest declares is not what an app ships.** The customer app
      declares four permissions and **ships sixteen**; the rest arrive from
      libraries when the merger runs, and Play lists all of them. Every entry was
      read out of the **built release APK** with `aapt2 dump badging`, not out of
      the source manifests — the same lesson as S2's UTF-16 grep, that the
      artefact and the source disagree.

      **The three source manifests are already minimal and every declared line
      already carries its justification in a comment.** Nothing was removable.
      Two candidates were examined and both rejected on evidence:

      - **`ACCESS_FINE_LOCATION` in the customer app.** The code asks for
        `LocationAccuracy.medium`, which reads like COARSE would do — but the
        granted permission is the ceiling, and Android 12+ fuzzes an
        approximate-only grant to a ~3 km² grid. That is "Hyderabad" instead of
        "Banjara Hills", exactly the failure the existing comment describes. The
        FINE+COARSE pair is the correct pattern. **I was wrong and the manifest
        was right.**
      - **The four Razorpay permissions** (`NFC`, `READ_BASIC_PHONE_STATE`,
        `USE_BIOMETRIC`, `USE_FINGERPRINT`), which merge from the checkout AAR.
        NFC is genuinely dead in a UPI-only flow, but the payment path has never
        run against live Razorpay (S5) and an untested change to it before
        submission is the wrong trade. **They cost nothing on the listing:**
        `aapt2` confirms the SDK already ships `android.hardware.nfc` as
        `required="false"`, so **no device is filtered out.**

      **The only implied hardware features anywhere are `android.hardware.location`
      and the default `faketouch`** — neither excludes a real phone, so no
      `uses-feature` work is owed. `ACCESS_BACKGROUND_LOCATION` is absent from all
      three, which is right: the rider tracks inside a foreground service, which
      avoids Play's background-location review entirely.

      **Two answers the forms will need**, both written up in the register:
      `FOREGROUND_SERVICE_SPECIAL_USE` needs a Console justification (copy the
      `PROPERTY_SPECIAL_USE_FGS_SUBTYPE` text from the live-card manifest
      verbatim — a vague one is the usual rejection), and the customer's
      location prominent-disclosure screen, **now built — see A6.**

- [x] **A6 — The customer's location prominent disclosure.** ✅ **Closed 3 Aug.**
      Found by A4; the piece `LEG-001` deliberately left open. **Play rejects for
      its absence, and the rejection arrives after review rather than at upload**,
      so it costs a cycle rather than a re-upload.

      Google's User Data policy requires an *in-app* disclosure before the system
      location dialog, naming the data, saying what it is for, and taking an
      affirmative action. The system dialog cannot be that disclosure — it says
      "allow this app to access your location" and nothing about why.

      A sheet in the app's own idiom, shown **only when the system dialog is
      actually about to appear**: `needsPermissionPrompt()` answers false for both
      granted *and* permanently-denied, because a disclosure in front of either is
      a sheet arguing with a decision the customer already made. It makes three
      claims and **each is true of this build**, which is the point — the reviewer
      checks them against the app: foreground only (no
      `ACCESS_BACKGROUND_LOCATION` anywhere), never sold or shared for
      advertising (matches the privacy policy and D3's answers), and refusable
      (typing an address by hand reaches every screen the GPS path does).

      **Declining is silent.** No error, no red text: the customer did not fail to
      give us a location, they said no, and an error would be an argument with
      their answer. The saved-address list and the manual form are both still
      there.

      Both entry points are covered — the address picker sheet and the address
      form — because a disclosure on one of two doors is not a disclosure.
      `flutter analyze` clean.

      **The rider's disclosure is now built too — see A7.**
- [x] **A7 — The rider's prominent disclosure.** ✅ **Closed 3 Aug.** The half A6
      left open, and **not a copy of the customer's** — that app reads a location
      once to fill in an address; this one reports a position every 30 m for the
      whole of a delivery, into a screen a stranger is watching. A disclosure that
      did not say so would be accurate about the permission and misleading about
      the app.

      **The design question A6 appeared to leave open turned out not to be one.**
      "Does it fire at the online toggle or at job accept?" only arises if the
      disclosure lives at one point, which is the wrong shape: the policy asks for
      it *in front of the system dialog*, wherever that dialog appears. Keying it
      to permission state instead of to a screen answers it with no product
      decision — `ensureLocationDisclosed()` shows nothing unless
      `checkPermission()` is exactly `denied`. `deniedForever` shows nothing
      (Android will not raise the dialog again, so there is nothing to disclose in
      front of, and a sheet there argues with a decision already made), and
      granted shows nothing.

      **Both doors are covered, and neither knows about the other** — whichever
      runs second finds the permission settled and stays silent. The obstacle was
      that only one door has a `BuildContext`: `job_map_page` is a widget, but
      `RiderLocationReporter` is a provider-driven data class. Solved with an
      explicit `navigatorKey` on the existing GoRouter — **GoRouter makes one
      anyway when none is passed, so this changes nothing about routing and
      merely gives that key a name.** No architectural change, and the sheet lives
      in `core/widgets/` rather than under `features/jobs/presentation/`, because
      the reporter is in `data/` and importing presentation from there would have
      been the app's first such violation.

      **Four claims, each true of this build**, which is the point — the reviewer
      checks them: continuous *while carrying* and said plainly; a foreground-
      service notification visible the whole time it is on; never sold or shared
      for advertising; and refusable, because declining costs the rider nothing
      but the dot (0057 refuses a position from a rider with no live job anyway).
      Declining returns false and the reporter simply does not start — the outcome
      that class was already written to tolerate.

      `flutter analyze` clean (9 pre-existing issues, none in the touched files).
      **Still needs the listing's foreground-location declaration**, which is
      yours and is recorded in `PLAY_DATA_SAFETY.md`. **Not yet seen on a real
      screen** — the sheet has never been rendered on a device; that is a
      Phase 5 check.
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
- [ ] **The S4 pricing check, over HTTP with the signed-in session** — place one
      order, then compare `orders.total` against the cart's own figure. This is
      the one S4 claim proven in `psql` rather than through a real token, and a
      single real order settles it
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
