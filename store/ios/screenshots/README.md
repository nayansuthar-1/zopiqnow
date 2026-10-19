# iOS App Store screenshots — customer app

Captured 2026-09-12 from `main` @ 07dd444, iPhone 17 Pro Max simulator (iOS 26.5),
`xcrun simctl io … screenshot`, status bar overridden to 9:41.
**`02` was re-shot 2026-10-19** from the build-31 simulator binary — see below.

**Size: 1320×2868 = 6.9" (`APP_IPHONE_69`).** Note `IOS_APP_STORE_LISTING.md` §6 says
6.7"; that is stale. The live ASC listing currently holds a *6.5"* set
(`APP_IPHONE_65`) of three **landscape** 2778×1284 images, plus an
`IMESSAGE_APP_IPHONE_65` set for an app that has no iMessage extension.

Numbering follows `IOS_APP_STORE_LISTING.md` §6.

| # | File | State | Notes |
|---|---|---|---|
| 1 | `01-feed-sadri.png` | ❌ blocked | Feed, Bus Stand Road, Sadri. Top recommendations are the ₹1 test dishes |
| 2 | `02-restaurant-menu.png` | ✅ **re-shot 10-19** | **Shiv Fast Food** — Pure Veg, **1.0 km**, 35–40 min, dishes ₹70–₹110 with real photos and descriptions |
| 3 | `03-cart-bill.png` | ⚠️ old | Cart + Bill Details. Still the 09-12 capture |
| 4 | — | — | **Not captured.** Live tracking needs an order in flight |
| 5 | `05-gifts.png` | ⚠️ old | Gifts tab. Re-shot on 10-19 and the result was no better, so the original stands |
| 6 | `06-veg-mode.png` | ❌ blocked | Veg Mode on. Same ₹1 test dishes as `01` |

## What is actually blocking, as of 2026-10-19

**One row of production data blocks `01` and `06`.** The top recommendations are
₹1 dishes from **"Sadri Test Restaurant"**, and Apple rejects screenshots that
misrepresent the app. Hiding that restaurant in the admin panel fixes both shots
and nothing else needs to change. The owner is doing this.

**The "0.0 km" in the old `02` was never a bug, and must not be "fixed" in code.**
Both render sites already omit an unknown distance (`restaurant_card.dart:141`,
`menu_header.dart:200`) and `geo_distance.dart` exists precisely so unknown never
collapses into zero — all of it landed 2026-08-11, a month *before* those
captures. The real cause was the seeded screenshot address carrying coordinates
that sat on top of the restaurant's own. Seeded 1 km away on 10-19, the same
screen renders **"1.0 km"**. The old note below claimed a **0.0 ★** badge too;
it does not appear in any of these captures.

**Gift prices are partly real now.** The old note said every gift was the same
₹999/₹1249 placeholder; the 10-19 capture shows at least one at ₹499/₹624. They
remain largely obscured by the floating nav bar, which is why `05` was not
replaced.

## Re-shooting: the recipe that worked

`IOS_RELEASE_RUNBOOK.md` §A4 has the seeding mechanics. Three things it does not
say, learned on 10-19:

- **Seed `line1` *without* the town.** The header renders `"<line1>, <city>"`, so
  `line1: "Bus Stand Road, Sadri"` produces **"Bus Stand Road, Sadri, Sadri"**.
- **Seed coordinates a realistic distance from the restaurants**, or the distance
  line reads 0.0 km and looks like a bug. `25.1838, 73.4425` gives 1.0 km to Shiv
  Fast Food. Leave `service_area_id` null and let the app resolve the town — it
  did, to Sadri, 9 restaurants.
- **The hero banner rotates every launch** (50% off, ₹150 off, 60% off, Big Brand
  Heist…). Whichever is on screen when you shoot is what you get; there is no way
  to pin one.

⚠️ **Driving the simulator needs Accessibility permission**, and only for taps —
`xcrun simctl` cannot tap, and `simctl privacy` has **no `notifications` service**,
so the push-permission alert on first launch must be dismissed by hand or by a
synthesised click. Grant the terminal Accessibility under System Settings →
Privacy & Security, or the capture run stops at the first alert. That grant
lapsed mid-run on 10-19, which is why `03` is still the old capture.
