# What's left — all three apps

**As of 2026-07-30.** Short version. The long version lives in
[ZOMATO_PARITY.md](ZOMATO_PARITY.md) (Part B) and [VENDOR_TASKS.md](VENDOR_TASKS.md).

Shipped and not repeated here: ordering, live tracking, dispatch + offers, delivery
lifecycle with both OTPs, cancellation + accept timeout, push, notifications inbox in
all three apps, calls + canned chat (B5), ratings/reviews/GST invoice/offers (B6),
the admin console (B7 + all-orders), and vendor Phases 1–7 bar one item.

---

## Customer app

- **Payments** — still `MockPaymentGateway`. Razorpay checkout, server-created order,
  server-side signature verification. *(B4 — the next phase)*
- **Refunds** — no money ever comes back. Refund on cancel/rejection, plus an
  order-issue / report screen. *(B2b, deferred behind B4)*
- **Account tiles that lie** — Payment Methods, Offers, Help & Support, Settings and
  See Recommendation are "coming soon" snackbars. Help & Support matters most: it is
  the front door for B2b's support queue.
- **Gifts** — browse-only. Needs a separate gift cart and checkout. *(Not food delivery.)*

## Vendor app

- ~~**Sound + haptic** on a new order in the foreground.~~ **Already done** — struck
  2026-07-30. `new_order_alarm.dart` fires `HapticFeedback.heavyImpact()` and
  `PushService.chimeNewOrder()`, adopts the first batch silently so a morning
  launch does not ring nine times, is wired into `vendor_shell.dart`, and is
  covered by `new_order_alarm_test.dart`. It had been carried here as owed since
  Phase 7 and a launch audit re-reported it as missing on the strength of this
  line. A stale tracker costs more than an untracked task.
- Phase 9 hardening folds into B8 below.

## Rider app

- **KYC** — document upload, admin verification. *(B8)*
- Navigation is a `geo:` hand-off to the phone's maps app; in-app turn-by-turn is not
  planned.

## Backend / admin (cuts across all three)

- `supabase functions delete send-order-push` — unwired since 0058, still ACTIVE.
- Hardening: fraud limits (velocity, concurrent-claim cap, OTP attempt caps),
  `revoke all on function` sweep, `/security-review` over every RPC added since B1,
  release-APK manifest check per app, Android 10 perf pass. *(B8)*

## Known limitations, accepted rather than owed

Prep time cannot be revised after accepting · no rider photo (the roster stores none) ·
pickup QR not built, the OTP covers it.

---

**Order of work:** B4 payments → B2b refunds → B8 hardening.

**Housekeeping:** `supabase migration list` shows 0062–0069 as local-only. The objects
are live — those migrations were applied by hand — but
`supabase_migrations.schema_migrations` never got the rows, so the CLI's ledger
disagrees with the database. Worth reconciling before anything relies on it.

**External blockers (PM, not code):** Razorpay KYC, DLT/SMS registration, Play Console
verification, privacy policy URL. See [PM_CHECKLIST.md](PM_CHECKLIST.md).
