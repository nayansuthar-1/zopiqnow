# What's left — all three apps

**As of 2026-08-04.** Short version. The queue that actually decides what gets
done now is [SHIP_PLAN_ANDROID_IOS.md](SHIP_PLAN_ANDROID_IOS.md); the long-form
backlog lives in [ZOMATO_PARITY.md](ZOMATO_PARITY.md) (Part B),
[VENDOR_TASKS.md](VENDOR_TASKS.md) and [AUDIT_CHECKLIST.md](AUDIT_CHECKLIST.md).

> **This file was four days stale and most of it was wrong.** The 30 July version
> still listed payments as `MockPaymentGateway`, the rider's KYC as unbuilt, the
> `revoke` sweep as owed and a dead edge function as live — all four had shipped.
> Every line below was checked against the code or the live database on 4 August,
> not carried forward. A stale tracker costs more than an untracked task.

Shipped and not repeated here: ordering, live tracking, dispatch + offers,
delivery lifecycle with both OTPs, cancellation + accept timeout, push,
notifications inbox in all three apps, calls + canned chat (B5),
ratings/reviews/GST invoice/offers (B6), the admin console (B7 + all-orders +
People), rider KYC (B8/0080), vendor Phases 1–7, and the Phase 1 security sweep
(S1–S9, migrations 0087–0093).

---

## The only thing between here and a Play submission

Everything in this section is **yours**, not code. Nothing in the repo blocks a
submission today.

- **G1 Apple Developer Program enrolment** — the iOS gate, and the only item with
  a queue. Every iOS task is downstream of the certificate it issues.
- **G3 Razorpay merchant KYC** — until the live keys exist, the payment gate
  (S5) stays disarmed and no real money can move.
- **G4 Host the legal documents at a public URL** — files moved to `docs/` and
  ready; enabling Pages (Settings → Pages → `main` / `/docs`) is the last step.
- ~~**G5 Rotate the leaked Resend key**~~ — **closed 4 Aug as an accepted risk.**
  The owning account is unreachable so the key stays live and public, but with no
  verified domain it cannot send to arbitrary recipients and grants nothing
  beyond an unused Resend account. **Never verify a domain on that account.**
- **G6 Enable PITR**, **G11 restrict the Maps key**, **G12 cap the Cloudinary
  preset** — three dashboard settings, each the only control that exists for the
  thing it protects.
- **G13 `rate_limit_verify` → 200** — still 30, and it caps successful sign-ins
  at 30/hour across all three apps. Two of the three limits are already raised.
- **G9 keystore passwords** — the keystores now exist (A2); what is owed is
  copying the two passwords and the two `.jks` files somewhere off this laptop.
- **D1–D6** — store assets, listings, declarations, a reviewer test account.

## Customer app

- **Payments** — Razorpay is shipped and verified server-side (B4: intents, HMAC
  check, the 0085 trigger). What remains is not code: the gate is armed with one
  SQL statement once G3 lands, and it ends with **one real ₹1 payment on a real
  device per platform**. The signature path has never run against Razorpay, only
  against a known-good vector.
- **Account tiles that lie** — Payment Methods, Offers, Help & Support, Settings
  and See Recommendation are still "coming soon". Help & Support matters most: it
  is the front door for the support queue (ADM-002), and at launch volume phone
  and WhatsApp cover it.
- **Gifts** — still browse-only. Needs a separate gift cart and checkout. Not
  food delivery, and not a launch blocker.

## Vendor app

- Nothing owed for launch. Phase 3 (menu) closed with 0068; a real release
  keystore landed with A2.

## Rider app

- **KYC is done** (0080, verified against the live function bodies in S9). The
  one thing S9 deliberately left to you: should an override with
  `override_until = null` keep meaning *permanent*? That is a judgement about
  people's livelihoods, not a schema change.
- Navigation is an in-app map with an "Open in Maps" hand-off; turn-by-turn is
  not planned.

## Backend / admin (cuts across all three)

- **Done since the last revision:** `send-order-push` deleted (it was a live
  *unauthenticated* push endpoint, not housekeeping — G7); `ola-static` deleted;
  the `revoke ... from PUBLIC` sweep (0087) and the write-grant sweep (0089);
  rate limits on orders, broadcasts, chat and payment intents (0090, 0091); the
  `admin_actions` audit trail (0092); the service-role key removed from the
  notifications webhook (0091).
- **Two standing checks must return zero rows before every release** — in the
  footers of `0087_a_revoke_that_did_nothing.sql` and
  `0089_a_grant_nobody_asked_for.sql`. **Both returned zero on 4 August.**
- **Still open:** SEC-003, one flat admin role with no MFA — deferred until a
  second admin account exists; 0092 buys the audit trail in the meantime.

## Known limitations, accepted rather than owed

Prep time cannot be revised after accepting · no rider photo (the roster stores
none) · pickup QR not built, the OTP covers it · "nearby" is a number an admin
typed (FEA-001 — fine for one area, urgent at the second) · no phone-number auth
(UX-002 — a conversion problem, not a broken app) · nothing paginated · no tests
on the money layer (QA-001 — first thing after both listings are live).

---

**Order of work:** the Phase 0 items above (all yours) → A5 device smoke on
release builds → Play submission → iOS once G1 clears.

**Housekeeping:** the CLI's migration ledger has disagreed with the live database
four times. Migrations are applied by hand and
`supabase_migrations.schema_migrations` never gets the rows, so
`supabase migration list` under-reports. **Verify the schema, never the ledger.**

**External blockers (PM, not code):** see the top section and
[PM_CHECKLIST.md](PM_CHECKLIST.md).
