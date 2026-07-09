# Zopiqnow — What we need from the Project Manager

**Date:** 2026-07-10
**Purpose:** decisions, accounts, and assets the dev side needs *in advance*. Items
marked ⏳ have real lead time (days–weeks of paperwork) — start those first.

---

## 1. Start-immediately items (long lead time)

| # | Item | Why it's slow |
|---|---|---|
| 1 | ⏳ **DLT registration** (TRAI) — entity, sender ID (header), and OTP SMS template registered on a DLT portal (Jio/Airtel/Vodafone TrataDLT) | Mandatory for sending any SMS in India. Approval takes days–weeks; **no OTP SMS can go out without it** |
| 2 | ⏳ **Razorpay account + KYC** — business PAN, bank account, GST, website/app URL | Activation review takes days; needed before any real payment test (UPI/COD flows) |
| 3 | ⏳ **Google Play Console account** — org account, D-U-N-S number, business verification, $25 fee | Verification can take weeks; without it we cannot even do closed testing |
| 4 | ⏳ **Privacy policy + Terms of Service, hosted at a public URL** | Play Store requires it (we use phone number + location). Needs legal review |
| 5 | ⏳ **FSSAI position** — does the platform need an aggregator/e-commerce FSSAI license? Restaurants' FSSAI numbers must be shown on orders | Regulatory; legal/CA input needed |

## 2. Database & backend infrastructure (decisions needed)

- **Database plan.** Recommendation: **managed PostgreSQL + PostGIS** (geo queries:
  "restaurants within X km", rider tracking). Options, pick one:
  - *MVP-friendly:* Supabase Pro (~$25/mo) or Neon Scale — fast to stand up, easy to grow.
  - *Cloud-native:* AWS RDS / GCP Cloud SQL in **ap-south-1 / asia-south1 (Mumbai)** —
    more setup, better long-term control.
  - Either way: start ~2 vCPU / 8 GB, autoscaling storage, automated backups + PITR.
- **Redis** (managed) — OTP rate-limiting, sessions, cart cache, hot restaurant lists.
  Upstash / ElastiCache / Memorystore, smallest tier is fine at launch.
- **Backend hosting** — where does the API run? (Railway/Render for speed vs
  AWS/GCP for control.) Region must be Mumbai for latency.
- **Realtime channel for order tracking** — WebSockets on our backend vs a managed
  service (Ably/Pusher) vs Firebase. Needed by Step 8; decide by Step 7.
- **Environments** — confirm we get separate dev/staging/prod projects & keys for
  every service below (never share prod keys with the app in testing).

## 3. SMS / OTP service

- Pick a provider (all need the DLT registration from §1):
  - **MSG91** — India-focused, good OTP APIs, cheap (~₹0.15–0.25/SMS).
  - **Kaleyra / Gupshup / Airtel IQ** — comparable, enterprise-leaning.
  - **Twilio** — easiest API, priciest for India volume.
  - **Firebase Phone Auth** — bundles OTP delivery, free tier, but locks auth to
    Firebase and monthly costs jump at scale.
- **WhatsApp OTP as a fallback/primary?** (Gupshup/MSG91) — cheaper per message,
  higher delivery rate; needs a WhatsApp Business account (also has lead time).
- We need: API keys (test + prod), the approved DLT template ID, sender ID.

## 4. Payments

- **Razorpay** (recommended, per plan Step 6): confirm account, and decide —
  - Payment methods at launch: UPI, cards, netbanking, wallets, **COD rules**?
  - Refund policy + who triggers refunds (support tooling?).
  - Settlement cadence and the bank account.
- Platform commission model per restaurant (%, flat?) — needed for order math.
- **Fee rules** (currently hardcoded in the app, plan §Known gaps): delivery fee
  slabs by distance, surge rules, packaging charges, GST treatment per item category,
  platform fee. We need the actual formula in writing.

## 5. Maps & location

- **Google Maps Platform billing account** (Places autocomplete for the add-address
  screen, Directions/Distance Matrix for delivery fee + ETA, Maps SDK for tracking).
  $200/mo free credit, then real money — or evaluate **Ola Maps / Mappls (MapmyIndia)**,
  which are significantly cheaper for India.
- Decision + API keys (restricted per-app) for dev and prod.

## 6. Images, storage & CDN

- **Who supplies restaurant/dish photos, and in what pipeline?** (Currently the app
  uses placeholder photo APIs.)
- Object storage + CDN + on-the-fly resizing: **ImageKit** (India-friendly, free tier)
  or **Cloudinary**, or S3+CloudFront. Decide one; we need upload credentials and a
  base URL.
- **Hero/banner artwork** for the new homepage hero — final image(s) from design
  (portrait ~1290×1100+, safe-area notes). A temporary in-app version ships until then.
- Category illustrations to replace OpenMoji art (licensing decision).
- Final **app icon**, splash, and Play Store assets (feature graphic, screenshots).
- **Proxima Nova license** — buy or stay on Figtree? (One-line swap either way.)

## 7. Push notifications, analytics, crash reporting

- **Firebase project** (org-owned, not a personal account): FCM for push (free),
  Crashlytics, Analytics. We need to be added as members.
- Or Sentry for crashes if we're avoiding Firebase — decide one.
- Who writes/approves push campaign content vs transactional pushes (order status)?

## 8. Restaurant content & operations (data we cannot invent)

- **Onboarding sheet per restaurant:** name, address + lat/lng, FSSAI number, GST
  number, cuisines, hours, full menu with prices, veg/non-veg flags, item photos,
  packaging charge, prep-time estimate.
- Commercial terms per restaurant (commission, exclusivity, discounts funded by whom).
- **Coupon/offer rules** for launch (codes, caps, funding source).
- Delivery zone(s) for launch — which localities, radius per restaurant.
- Support channel: phone/WhatsApp/email for order issues; who staffs it.

## 9. Dining / table booking (new scope) — product decisions needed

- Which restaurants take bookings at launch, and **where does slot inventory come
  from** (restaurant-managed app? manual ops? fixed slots?).
- Party size limits, advance-booking window, same-day cutoff.
- **Deposits / booking fees?** No-show policy? Cancellation window + refund rule?
- Confirmation channel (in-app only, or SMS/WhatsApp to user + restaurant?).
- Any dining offers ("flat 20% off bill") — who funds, how validated at the table?

## 10. Business & legal odds-and-ends

- Legal entity name exactly as it should appear in the app/store/invoices.
- **GST invoicing** requirements for customer receipts.
- Support email + phone for the Play listing.
- Domain name(s) — api.___, images.___, and the privacy-policy host.
- Trademark check on "Zopiqnow" branding before spending on assets.
- Budget ceiling per month for all the above so we can size the tiers.

---

**TL;DR for the PM — five things to kick off *today*:** DLT registration, Razorpay
KYC, Play Console business verification, privacy policy/ToS, and a decision on the
database + SMS provider so dev isn't blocked at Step 7.
