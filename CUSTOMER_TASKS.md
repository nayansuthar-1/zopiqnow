# Zopiqnow Customer App — Roadmap

A short status tracker for `apps/customer`. Tick boxes as work lands.
`[x]` done · `[~]` partial · `[ ]` pending.

---

## Core flow (order a meal end-to-end)

- [x] **Auth** — email OTP (Brevo), splash/session restore, route guard, delivery-phone sheet
- [~] Auth — Google sign-in (wiring owed; `google_sign_in` approval pending)
- [x] **Home feed** — restaurants, hero carousel, offers carousel, deal/category/top-chains rails, filter chips
- [x] **Search** — restaurants/dishes
- [x] **Menu** — categories, items, veg/non-veg, add-to-cart control
- [x] **Cart** — add/remove, quantities, docked cart bar, bill summary
- [x] **Checkout** — address pick, coupon apply, payment-method select, bill breakdown
- [~] Payment — **mock gateway only**; real Razorpay + backend order pending
- [x] **Order** — place → success screen → history list → order detail
- [x] **Addresses** — device location, address book, add/edit form
- [x] **Favourites** — save/unsave restaurants + favourite button
- [x] **Account** — profile page + edit details

## Supporting / minor features

- [x] Coupons — apply/remove, discount in bill
- [x] Loading skeletons + empty/error state views
- [x] Dark / light theme (Swiggy tokens)
- [x] Cloudinary images, cached
- [x] Licenses / attributions page
- [x] Design-system showcase (debug)
- [ ] Reorder / repeat past order
- [ ] Address labels & default address polish
- [ ] Share restaurant / referral link

## Pending / next up

- [ ] Real payment gateway (Razorpay + create-order backend)
- [ ] Live order tracking (status timeline, rider, map/ETA)
- [ ] Push notifications (order updates, promos)
- [ ] Ratings & reviews (rate order, review restaurant)
- [ ] Help / support (contact, FAQ, order issues)

## Other verticals (stubbed "coming soon")

- [ ] Dining tab
- [ ] Grocery tab
- [ ] Wallet / loyalty / referrals

---

**Status:** core food-delivery journey is built and working on mocked payments.
The gap to production is real payments, live tracking, notifications, and reviews.
